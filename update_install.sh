sed -i 's/main "$@"/if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then main "$@"; fi/' scripts/install.sh
