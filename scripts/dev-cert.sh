#!/usr/bin/env bash
# Tworzy lokalny, samopodpisany certyfikat „Wyspa Development” do podpisywania kodu
# i importuje go do pęku kluczy logowania. Dzięki stałemu podpisowi macOS pamięta
# zgody (Dostępność, Kalendarze, Kamera) między kolejnymi buildami.
#
# Certyfikat służy tylko do lokalnego podpisu. Nie dodaje zaufania systemowego.
set -euo pipefail

NAME="Wyspa Development"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "Certyfikat „${NAME}” już istnieje."
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PASSWORD="$(uuidgen)"

cat > "$WORK/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/cert.cnf" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -name "$NAME" -out "$WORK/cert.p12" -passout "pass:$PASSWORD"

security import "$WORK/cert.p12" -k "$KEYCHAIN" -P "$PASSWORD" -T /usr/bin/codesign

echo "Zaimportowano certyfikat „${NAME}”."
echo "Przy pierwszym podpisie macOS może zapytać o dostęp codesign do klucza: wybierz „Zawsze pozwalaj”."
