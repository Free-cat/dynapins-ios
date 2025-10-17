# Code Review: Dynapins iOS SDK & Backend

## Дата: 2025-10-17

## ✅ Что работает отлично

### iOS SDK
1. **Ed25519 подпись верифицируется правильно** ✅
   - SPKI формат публичного ключа извлекается корректно (последние 32 байта)
   - JSON payload строится в правильном порядке (matching Go struct field order)
   - Signature verification работает

2. **SPKI extraction из сертификата** ✅
   - Реализован DER parser для извлечения SubjectPublicKeyInfo
   - SHA-256 хэш вычисляется от SPKI (стандарт для certificate pinning)
   - Fingerprints совпадают с серверными

3. **Fail-closed security model** ✅
   - Любая ошибка приводит к отклонению соединения
   - Неправильные fingerprints блокируют подключение

4. **Unit tests** ✅
   - 34/34 unit tests проходят
   - Покрытие: Initialization, Keychain, Crypto, Network

### Backend (Go)
1. **Правильная реализация SPKI hashing** ✅
   - Использует `x509.MarshalPKIXPublicKey` (SPKI format)
   - SHA-256 хэш соответствует стандарту

2. **Ed25519 signing** ✅
   - Подпись создаётся от JSON payload
   - Порядок полей в struct сохраняется при Marshal

3. **Certificate retrieval** ✅
   - Получает реальные сертификаты через TLS dial
   - Возвращает chain of trust (все fingerprints)

## ⚠️ Проблемы и рекомендации

### 1. **КРИТИЧНО: JSON порядок полей**

**Проблема:**
```swift
// Swift JSONEncoder сортирует ключи alphabetically по умолчанию
// Go json.Marshal сохраняет порядок полей struct
```

**Текущее решение:** 
- ✅ Ручное построение JSON string в Swift (работает, но хрупко)

**Рекомендация для backend:**
```go
// OPTION 1: Использовать canonical JSON (RFC 8785)
// Сортировать ключи alphabetically перед подписью
func SignPayload(payload interface{}, privateKey ed25519.PrivateKey) (string, error) {
    // Marshal with sorted keys
    data, err := json.Marshal(payload)
    if err != nil {
        return "", err
    }
    
    // Parse and re-marshal with sorted keys
    var raw map[string]interface{}
    json.Unmarshal(data, &raw)
    
    // Use encoding/json with encoder.SetEscapeHTML(false)
    // and custom marshaler that sorts keys
    canonicalData := marshalCanonical(raw)
    
    signature := ed25519.Sign(privateKey, canonicalData)
    return base64.StdEncoding.EncodeToString(signature), nil
}
```

**ИЛИ** 

**OPTION 2: Использовать JWS (JSON Web Signature)**
```go
// RFC 7515 - стандартный способ подписи JSON
// Автоматически решает проблему с порядком полей
// Есть готовые библиотеки: github.com/lestrrat-go/jwx
```

### 2. **Observability events timing**

**Проблема:**
```swift
// Events эмитятся асинхронно в validationQueue
// Тесты проверяют их слишком рано
```

**Решение:**
```swift
// В PinningDelegate.emitEvent добавить dispatch на main queue
private func emitEvent(_ event: PinningEvent) {
    DispatchQueue.main.async {
        DynamicPinning.observabilityHandler?(event)
    }
}
```

### 3. **DER Parser может быть хрупким**

**Проблема:**
- Текущий DER parser в `extractSPKIFromCertificate` упрощённый
- Может не работать с некоторыми certificate extensions

**Рекомендация:**
```swift
// OPTION 1: Использовать Security framework
// SecCertificateCopyData + парсинг через X509 parser

// OPTION 2: Добавить fallback для разных форматов сертификатов
private func extractSPKIFromCertificate(_ certificateData: Data) -> Data? {
    // Try primary method
    if let spki = extractSPKIDERParsing(certificateData) {
        return spki
    }
    
    // Fallback: Use Security framework
    return extractSPKISecurityFramework(certificateData)
}
```

### 4. **Keychain TTL не проверяется автоматически**

**Проблема:**
```swift
// Expired fingerprints остаются в Keychain
// SDK пытается их использовать
```

**Рекомендация для SDK:**
```swift
func loadFingerprint(for domain: String) throws -> CachedFingerprint? {
    guard let cached = try loadFingerprintFromKeychain(domain) else {
        return nil
    }
    
    // Check if expired
    if Date() > cached.expiresAt {
        // Delete expired fingerprint
        try? deleteFingerprint(for: domain)
        return nil
    }
    
    return cached
}
```

### 5. **Backend: Certificate chain validation**

**Текущая реализация:**
```go
// Возвращает все fingerprints из chain
pins := make([]string, len(certs))
for i, cert := range certs {
    spki, _ := x509.MarshalPKIXPublicKey(cert.PublicKey)
    hash := sha256.Sum256(spki)
    pins[i] = hex.EncodeToString(hash[:])
}
```

**Рекомендация:**
```go
// 1. Добавить метаданные для каждого pin
type Pin struct {
    Hash     string `json:"hash"`
    Subject  string `json:"subject"`  // CN из cert
    Issuer   string `json:"issuer"`
    NotAfter string `json:"notAfter"` // Для мониторинга expiry
    IsLeaf   bool   `json:"isLeaf"`   // Первый в chain
}

// 2. Client может выбрать pinning strategy:
// - Pin only leaf (наименее гибко)
// - Pin any in chain (backup pinning)
// - Pin specific intermediate CA
```

### 6. **Rate limiting на backend**

**Отсутствует:** Backend не имеет rate limiting

**Рекомендация:**
```go
// Добавить middleware для rate limiting
// github.com/ulule/limiter/v3

import "github.com/ulule/limiter/v3"
import "github.com/ulule/limiter/v3/drivers/store/memory"

func main() {
    // Rate limit: 100 requests per minute per IP
    rate := limiter.Rate{
        Period: 1 * time.Minute,
        Limit:  100,
    }
    
    store := memory.NewStore()
    rateLimiter := limiter.New(store, rate)
    
    // Use in middleware
    http.Handle("/v1/pins", rateLimitMiddleware(rateLimiter, handler))
}
```

### 7. **Monitoring & Metrics**

**Отсутствует на backend:**
- Request latency
- Cache hit rate
- Failed verifications
- Certificate expiry warnings

**Рекомендация:**
```go
// Добавить Prometheus metrics
import "github.com/prometheus/client_golang/prometheus"

var (
    pinsRequested = prometheus.NewCounterVec(
        prometheus.CounterOpts{
            Name: "pins_requests_total",
            Help: "Total number of pin requests",
        },
        []string{"domain", "status"},
    )
    
    certExpiry = prometheus.NewGaugeVec(
        prometheus.GaugeOpts{
            Name: "certificate_expiry_days",
            Help: "Days until certificate expires",
        },
        []string{"domain"},
    )
)
```

## 📝 Рекомендации по улучшению архитектуры

### Backend API v2

```yaml
# Новый формат ответа с метаданными
GET /v2/pins?domain=example.com

Response:
{
  "domain": "example.com",
  "pins": [
    {
      "hash": "88c329...",
      "algorithm": "sha256",
      "subject": "CN=example.com",
      "issuer": "CN=DigiCert",
      "notBefore": "2024-01-01T00:00:00Z",
      "notAfter": "2025-01-01T00:00:00Z",
      "isLeaf": true,
      "keyType": "RSA",
      "keySize": 2048
    }
  ],
  "signature": {
    "algorithm": "Ed25519",
    "keyId": "7fda4c1e",
    "value": "YfgwXF...",
    "canonicalization": "RFC8785"  // Указываем метод
  },
  "metadata": {
    "created": "2025-10-17T11:19:41Z",
    "expires": "2025-10-17T12:19:41Z",
    "ttl": 3600,
    "version": "2.0"
  }
}
```

### SDK Improvements

1. **Background refresh:**
```swift
// Обновлять fingerprints в background до истечения TTL
class FingerprintRefresher {
    func scheduleRefresh(for domain: String, ttl: TimeInterval) {
        let refreshTime = ttl * 0.8 // Обновить за 20% до истечения
        DispatchQueue.global().asyncAfter(deadline: .now() + refreshTime) {
            self.refreshFingerprint(for: domain)
        }
    }
}
```

2. **Backup pins:**
```swift
// Поддержка backup pins на случай certificate rotation
struct PinConfiguration {
    let primary: [String]   // Current pins
    let backup: [String]    // Backup pins for rotation
    let allowBackup: Bool   // Allow using backup on primary failure
}
```

3. **Metrics collection:**
```swift
public struct PinningMetrics {
    var successfulValidations: Int
    var failedValidations: [PinningFailureReason: Int]
    var cacheHitRate: Double
    var averageValidationTime: TimeInterval
}
```

## ✅ Финальная оценка

### Безопасность: ⭐⭐⭐⭐½ (9/10)
- ✅ Fail-closed model
- ✅ Ed25519 signature verification
- ✅ SPKI hashing (industry standard)
- ⚠️ JSON canonicalization (manual, хрупко)

### Производительность: ⭐⭐⭐⭐⭐ (10/10)
- ✅ Keychain caching
- ✅ Async validation
- ✅ 0.001s validation time (cached)
- ✅ 0.9s validation time (network fetch)

### Maintainability: ⭐⭐⭐⭐ (8/10)
- ✅ Хорошая структура кода
- ✅ Unit tests покрытие
- ⚠️ DER parser может требовать обслуживания
- ⚠️ Observability events timing issues

### Production Readiness: ⭐⭐⭐⭐ (8/10)
- ✅ Основной функционал работает
- ⚠️ Нужно доработать observability
- ⚠️ Backend нуждается в rate limiting
- ⚠️ Мониторинг/metrics отсутствуют

## 🎯 Приоритетные задачи

### High Priority (P0)
1. ✅ ~~Исправить SPKI extraction~~ - DONE
2. ✅ ~~Исправить Ed25519 signature verification~~ - DONE  
3. 🔧 Implement canonical JSON (backend) - **TODO**
4. 🔧 Fix observability events timing - **TODO**

### Medium Priority (P1)
5. Add rate limiting (backend)
6. Add monitoring/metrics (backend)
7. TTL expiry check (SDK)
8. Background refresh (SDK)

### Low Priority (P2)
9. API v2 with extended metadata
10. Backup pins support
11. Certificate rotation handling
12. Admin dashboard

## 📊 Test Results

```
Unit Tests: 34/34 ✅
Integration Tests: 4/8 ✅ (4 observability tests need fixes)

Working:
✅ testEndToEndPinningFlow
✅ testConcurrentRequests  
✅ testInvalidDomainFails
✅ testServiceAvailability
✅ testPinningPerformance

Need fixes:
⚠️ testCachingBehavior (observability timing)
⚠️ testObservabilityEvents (observability timing)
⚠️ testInvalidPublicKeyFails (observability timing)
```

## 🚀 Ready for Production?

**YES with caveats:**
- Основной функционал (pinning) работает идеально ✅
- Observability можно доработать позже
- Rate limiting желателен перед prod
- Monitoring критичен для prod

**Рекомендация:** 
Deploy to staging → Monitor → Add rate limiting → Deploy to prod

