export PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export LC_ALL=C.UTF-8

load_lib() {
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/lib/$1"
}
