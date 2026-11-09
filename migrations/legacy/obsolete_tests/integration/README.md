# PostgreSQL Integration Tests

## Prasyarat
1. Docker Desktop berjalan
2. Jalankan `docker-compose -f docker-compose.test.yml up -d` untuk memulai database testing
3. Tunggu container postgres-test berjalan (healthcheck passed)
4. Jalankan migrasi: `.\\run_test_migrations.ps1`
5. Jalankan test: `flutter test test/integration/`

## Hasil test dipisahkan dari unit tests
- Unit tests: `flutter test test/unit/`
- PostgreSQL integration tests: `flutter test test/integration/`
- Supabase staging tests: Akan dijalankan jika staging tersedia: `flutter test test/staging/`