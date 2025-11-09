#!/bin/bash

#############################################
# Secure Environment Manager
# For encrypted credential storage
#############################################

ENV_DIR="${HOME}/.config/reddit-threat-intel"
ENCRYPTED_ENV="${ENV_DIR}/credentials.enc"
SALT_FILE="${ENV_DIR}/salt"

# Initialize secure environment
init_secure_env() {
    mkdir -p "${ENV_DIR}"
    chmod 700 "${ENV_DIR}"
    
    if [[ ! -f "${SALT_FILE}" ]]; then
        openssl rand -base64 32 > "${SALT_FILE}"
        chmod 600 "${SALT_FILE}"
    fi
    
    echo "Secure environment initialized at: ${ENV_DIR}"
}

# Encrypt credentials
encrypt_credentials() {
    local plaintext_file=$1
    
    if [[ ! -f "${plaintext_file}" ]]; then
        echo "Error: File not found: ${plaintext_file}"
        return 1
    fi
    
    echo "Enter encryption password:"
    read -rs password
    
    # Encrypt using AES-256-CBC
    openssl enc -aes-256-cbc -salt -pbkdf2 \
        -in "${plaintext_file}" \
        -out "${ENCRYPTED_ENV}" \
        -pass pass:"${password}"
    
    chmod 600 "${ENCRYPTED_ENV}"
    echo "Credentials encrypted successfully!"
    echo "Encrypted file: ${ENCRYPTED_ENV}"
}

# Decrypt credentials
decrypt_credentials() {
    if [[ ! -f "${ENCRYPTED_ENV}" ]]; then
        echo "Error: No encrypted credentials found"
        return 1
    fi
    
    echo "Enter decryption password:"
    read -rs password
    
    # Decrypt to stdout
    openssl enc -aes-256-cbc -d -pbkdf2 \
        -in "${ENCRYPTED_ENV}" \
        -pass pass:"${password}" 2>/dev/null
}

# Load encrypted credentials into environment
load_encrypted_env() {
    if [[ ! -f "${ENCRYPTED_ENV}" ]]; then
        return 1
    fi
    
    echo "Enter password to load credentials:"
    read -rs password
    
    local decrypted=$(openssl enc -aes-256-cbc -d -pbkdf2 \
        -in "${ENCRYPTED_ENV}" \
        -pass pass:"${password}" 2>/dev/null)
    
    if [[ $? -eq 0 ]]; then
        set -a
        eval "${decrypted}"
        set +a
        echo "Credentials loaded successfully!"
        return 0
    else
        echo "Error: Failed to decrypt credentials"
        return 1
    fi
}

# Store a single secret
set_secret() {
    local key=$1
    local value=$2
    
    init_secure_env
    
    # Create or update encrypted store
    local temp_env=$(mktemp)
    
    if [[ -f "${ENCRYPTED_ENV}" ]]; then
        decrypt_credentials > "${temp_env}" 2>/dev/null || true
    fi
    
    # Add or update the key
    if grep -q "^${key}=" "${temp_env}" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "${temp_env}"
    else
        echo "${key}=${value}" >> "${temp_env}"
    fi
    
    # Re-encrypt
    encrypt_credentials "${temp_env}"
    rm -f "${temp_env}"
}

# Get a single secret
get_secret() {
    local key=$1
    
    decrypt_credentials 2>/dev/null | grep "^${key}=" | cut -d= -f2-
}

# Main command handler
case "${1:-}" in
    init)
        init_secure_env
        ;;
    encrypt)
        encrypt_credentials "${2:-.env}"
        ;;
    decrypt)
        decrypt_credentials
        ;;
    load)
        load_encrypted_env
        ;;
    set)
        set_secret "$2" "$3"
        ;;
    get)
        get_secret "$2"
        ;;
    *)
        echo "Usage: $0 {init|encrypt|decrypt|load|set|get}"
        echo ""
        echo "Commands:"
        echo "  init              - Initialize secure environment"
        echo "  encrypt <file>    - Encrypt credentials file"
        echo "  decrypt           - Decrypt and show credentials"
        echo "  load              - Load credentials into environment"
        echo "  set <key> <value> - Store a secret"
        echo "  get <key>         - Retrieve a secret"
        exit 1
        ;;
esac
