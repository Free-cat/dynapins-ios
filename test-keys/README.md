# Test Keys for E2E Testing

This directory contains **test-only** Ed25519 keypair used for end-to-end integration tests.

⚠️ **IMPORTANT**: These keys are for **testing purposes only** and are committed to the repository. **DO NOT use them in production!**

## Files

- `private_key.pem` - Ed25519 private key in PEM format (used by dynapins-server in tests)
- `public_key.pem` - Ed25519 public key in PEM format
- `public_key_base64.txt` - Base64-encoded public key (SPKI format, used by iOS SDK tests)

## Usage

### Server (Docker Compose)

The test server is configured to use this private key via `docker-compose.test.yml`:

```yaml
environment:
  PRIVATE_KEY_PEM: |
    -----BEGIN PRIVATE KEY-----
    MC4CAQAwBQYDK2VwBCIEIEottsHhxfNBdKlEbCVOJZ0Pav1mfvjUruTuJMApfwjM
    -----END PRIVATE KEY-----
```

### Client (iOS SDK Tests)

The integration tests use the Base64-encoded public key:

```swift
let publicKey = "MCowBQYDK2VwAyEA9gocJEBHG+vcm2OH42ZEy8XiYarSBJ3ZBTA5Ni7J+Ac="
```

## Regenerating Keys

If you need to regenerate the test keys:

```bash
# Generate private key
openssl genpkey -algorithm ED25519 -out private_key.pem

# Extract public key
openssl pkey -in private_key.pem -pubout -out public_key.pem

# Generate Base64-encoded public key
openssl pkey -in public_key.pem -pubin -outform DER | base64 > public_key_base64.txt

# Update docker-compose.test.yml with the new private key
# Update Scripts/export-test-vars.sh with the new public key
```

## Security Note

These keys are intentionally committed to the repository for testing purposes. In production:

1. Generate unique keys for each environment
2. Store keys securely (e.g., AWS Secrets Manager, HashiCorp Vault, etc.)
3. Never commit production keys to version control
4. Rotate keys regularly
5. Use separate keys for each deployment environment

