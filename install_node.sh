#!/bin/bash

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
BOLD='\033[1m'
CYAN='\033[0;36m'
NC='\033[0m'

CONFIG_FILE="drosera_config.txt"
FORGE_BIN="forge"

print_message() {
    echo -e "${GREEN}[+] $1${NC}"
}

print_step() {
    echo -e "${YELLOW}\n=== $1 ===${NC}"
}

print_input() {
    echo -e "${BLUE}[?] $1${NC}"
}

print_error() {
    echo -e "${RED}[!] $1${NC}"
}

print_instruction() {
    echo -e "${BOLD}$1${NC}"
}

print_code() {
    echo -e "\n${BOLD}$1${NC}\n"
}

print_menu() {
    echo -e "${CYAN}$1${NC}"
}

check_result() {
    if [ $? -ne 0 ]; then
        print_error "$1"
        return 1
    fi
    return 0
}

reload_env() {
    print_message "Перезагружаем переменные окружения..."
    if [ -f "$HOME/.bashrc" ]; then
        source "$HOME/.bashrc" 2>/dev/null || . "$HOME/.bashrc"
        check_result "Не удалось перезагрузить .bashrc, но продолжаем работу" || true
    fi
    
    if [ -d "$HOME/.drosera/bin" ]; then
        export PATH="$HOME/.drosera/bin:$PATH"
    fi
    if [ -d "$HOME/.foundry/bin" ]; then
        export PATH="$HOME/.foundry/bin:$PATH"
    fi
    if [ -d "$HOME/.bun/bin" ]; then
        export BUN_INSTALL="$HOME/.bun"
        export PATH="$BUN_INSTALL/bin:$PATH"
    fi
    if [ -d "$HOME/.nvm" ]; then
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
    fi
}

command_exists() {
    command -v "$1" &> /dev/null
}

read_config() {
    print_step "Чтение конфигурационного файла"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "Конфигурационный файл $CONFIG_FILE не найден"
        print_message "Создайте файл $CONFIG_FILE со следующими параметрами:"
        echo "GITHUB_EMAIL=ваш_email@example.com"
        echo "GITHUB_USERNAME=ваше_имя_пользователя"
        echo "EVM_PRIVATE_KEY=ваш_приватный_ключ"
        echo "EVM_PUBLIC_ADDRESS=ваш_публичный_адрес"
        echo "HOLESKY_RPC=ваш_rpc_url"
        echo "SERVER_IP=ваш_ip_адрес"
        return 1
    fi
    
    print_message "Чтение параметров из конфигурационного файла $CONFIG_FILE..."
    source "$CONFIG_FILE"
    
    EVM_PRIVATE_KEY=${EVM_PRIVATE_KEY#0x}
    
    if [ -z "$GITHUB_EMAIL" ] || [ -z "$GITHUB_USERNAME" ] || [ -z "$EVM_PRIVATE_KEY" ] || 
       [ -z "$EVM_PUBLIC_ADDRESS" ] || [ -z "$HOLESKY_RPC" ] || [ -z "$SERVER_IP" ]; then
        print_error "В конфигурационном файле отсутствуют необходимые параметры"
        return 1
    fi
    
    print_message "Параметры успешно загружены из конфигурационного файла"
    print_message "GitHub Email: $GITHUB_EMAIL"
    print_message "GitHub Username: $GITHUB_USERNAME"
    print_message "Ethereum Address: $EVM_PUBLIC_ADDRESS"
    print_message "Holesky RPC URL: $HOLESKY_RPC"
    print_message "Server IP: $SERVER_IP"
    
    return 0
}

install_prerequisites() {
    print_step "ШАГ 1: Установка пререквизитов"
    
    install_docker
    
    install_drosera_cli
    
    install_foundry_cli
    
    install_bun
    
    install_nodejs
    
    load_drosera_operator_image
    
    print_step "Установка пререквизитов завершена!"
    print_message "Все компоненты успешно установлены"
    print_message "Для активации всех переменных окружения, выполните:"
    echo "source ~/.bashrc"
    print_message "Если forge не будет доступен после source, выполните:"
    echo "export PATH=\"\$HOME/.foundry/bin:\$PATH\""
    
    return 0
}

install_docker() {
    print_step "Проверка и установка Docker"
    
    if command_exists docker; then
        print_message "Docker уже установлен в системе"
        docker --version
        return 0
    fi
    
    print_message "Docker не найден. Начинаем установку..."
    
    print_message "Обновление пакетов..."
    sudo apt update -y && sudo apt upgrade -y
    check_result "Ошибка при обновлении пакетов" || true
    
    print_message "Удаление старых версий Docker..."
    for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do 
        sudo apt-get remove $pkg -y
    done
    
    print_message "Установка зависимостей..."
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg
    check_result "Ошибка при установке зависимостей" || true
    
    print_message "Настройка репозитория Docker..."
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    
    echo \
      "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    print_message "Обновление пакетов и установка Docker..."
    sudo apt update -y && sudo apt upgrade -y
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    check_result "Ошибка при установке Docker" || true
    
    print_message "Проверка установки Docker..."
    sudo docker run hello-world
    check_result "Ошибка при запуске тестового контейнера Docker" || true
    
    print_message "Docker успешно установлен!"
}

install_drosera_cli() {
    print_step "Установка Drosera CLI"
    
    print_message "Загрузка и установка Drosera..."
    curl -L https://app.drosera.io/install | bash
    check_result "Ошибка при установке Drosera" || true
    
    print_message "Обновление переменных окружения..."
    reload_env
    
    print_message "Запуск droseraup..."
    if command_exists droseraup; then
        droseraup
    elif [ -f "$HOME/.drosera/bin/droseraup" ]; then
        $HOME/.drosera/bin/droseraup
    elif [ -f "$HOME/.local/bin/droseraup" ]; then
        $HOME/.local/bin/droseraup
    else
        export PATH="$HOME/.drosera/bin:$PATH"
        $HOME/.drosera/bin/droseraup 2>/dev/null || true
    fi
    check_result "Ошибка при запуске droseraup" || true
}

install_foundry_cli() {
    print_step "Установка Foundry CLI"
    
    print_message "Загрузка и установка Foundry..."
    curl -L https://foundry.paradigm.xyz | bash
    check_result "Ошибка при установке Foundry" || true
    
    print_message "Обновление переменных окружения..."
    reload_env
    
    print_message "Запуск foundryup..."
    if command_exists foundryup; then
        foundryup
    elif [ -f "$HOME/.foundry/bin/foundryup" ]; then
        $HOME/.foundry/bin/foundryup
    else
        export PATH="$HOME/.foundry/bin:$PATH"
        $HOME/.foundry/bin/foundryup 2>/dev/null || true
    fi
    check_result "Ошибка при запуске foundryup" || true
    
    print_message "Обновление .bashrc для Foundry..."
    sed -i '/export PATH="$PATH:\/root\/.foundry\/bin"/d' "$HOME/.bashrc"
    sed -i '/export PATH="$PATH:\$HOME\/.foundry\/bin"/d' "$HOME/.bashrc"
    echo 'export PATH="$HOME/.foundry/bin:$PATH"' >> "$HOME/.bashrc"
    
    export PATH="$HOME/.foundry/bin:$PATH"
    
    if command_exists forge; then
        print_message "forge успешно установлен и доступен в PATH"
        forge --version
    else
        print_error "forge не найден в PATH после обновления"
        if [ -f "$HOME/.foundry/bin/forge" ]; then
            print_message "forge существует в ~/.foundry/bin, но не в PATH"
            print_message "После установки выполните: export PATH=\"$HOME/.foundry/bin:\$PATH\""
        fi
    fi
}

install_bun() {
    print_step "Установка Bun"
    
    print_message "Загрузка и установка Bun..."
    curl -fsSL https://bun.sh/install | bash
    check_result "Ошибка при установке Bun" || true
    
    print_message "Обновление переменных окружения..."
    reload_env
}

install_nodejs() {
    print_step "Установка Node.js"
    
    print_message "Установка NVM (Node Version Manager)..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    check_result "Ошибка при установке NVM" || true
    
    print_message "Загрузка NVM..."
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    
    print_message "Установка Node.js LTS..."
    nvm install --lts
    nvm use --lts
    check_result "Ошибка при установке Node.js" || true
    
    print_message "Установка глобальных npm пакетов..."
    if command_exists npm; then
        npm install -g yarn pm2 typescript ts-node
    fi
    check_result "Ошибка при установке npm пакетов" || true
}

load_drosera_operator_image() {
    print_step "Загрузка образа Drosera Operator"
    
    if ! command_exists docker; then
        print_error "Docker не установлен. Невозможно загрузить образ Drosera Operator"
        return 1
    fi
    
    if sudo docker images | grep -q "ghcr.io/drosera-network/drosera-operator"; then
        print_message "Образ Drosera Operator уже загружен"
        return 0
    fi
    
    print_message "Загрузка образа Drosera Operator..."
    sudo docker pull ghcr.io/drosera-network/drosera-operator:latest
    check_result "Ошибка при загрузке образа Drosera Operator" || true
    
    print_message "Образ Drosera Operator успешно загружен!"
}

deploy_contract_and_trap() {
    print_step "ШАГ 2: Развертывание контракта и трапа"
    
    check_forge || {
        print_error "Forge не доступен. Убедитесь, что Foundry установлен корректно."
        print_message "Попробуйте выполнить 'export PATH=\"$HOME/.foundry/bin:\$PATH\"' и запустить скрипт снова."
        return 1
    }
    
    setup_trap_directory || {
        print_error "Не удалось подготовить директорию для трапа"
        return 1
    }
    
    configure_git || {
        print_error "Не удалось настроить Git"
        return 1
    }
    
    initialize_trap || {
        print_error "Не удалось инициализировать трап"
        return 1
    }
    
    compile_trap || {
        print_error "Не удалось компилировать трап"
        return 1
    }
    
    deploy_trap
    
    print_step "Процесс развертывания Drosera Trap завершен!"
    print_message "Проверьте статус трапа в панели управления: https://app.drosera.io/"
    print_message "Подключите ваш кошелек и проверьте раздел 'Traps Owned'"
    
    return 0
}

check_forge() {
    print_step "Проверка доступности forge"
    
    export PATH="$HOME/.foundry/bin:$PATH"
    
    if command_exists forge; then
        print_message "forge доступен в PATH"
        forge --version
        FORGE_BIN="forge"
        return 0
    elif [ -f "$HOME/.foundry/bin/forge" ]; then
        print_message "forge найден в ~/.foundry/bin, но не в PATH"
        print_message "Используем полный путь к forge"
        $HOME/.foundry/bin/forge --version
        FORGE_BIN="$HOME/.foundry/bin/forge"
        return 0
    else
        print_error "forge не найден. Проверьте установку Foundry"
        print_message "Возможно, вам нужно сначала запустить скрипт установки пререквизитов"
        return 1
    fi
}

setup_trap_directory() {
    print_step "Создание директории для трапа"
    
    if [ -d "my-drosera-trap" ]; then
        print_message "Директория my-drosera-trap уже существует"
        print_input "Хотите использовать существующую директорию? (y/n): "
        read use_existing
        
        if [[ "$use_existing" != "y" && "$use_existing" != "Y" ]]; then
            print_message "Удаляем существующую директорию..."
            rm -rf my-drosera-trap
            mkdir my-drosera-trap
            check_result "Ошибка при создании директории my-drosera-trap" || return 1
        fi
    else
        print_message "Создание директории my-drosera-trap..."
        mkdir my-drosera-trap
        check_result "Ошибка при создании директории my-drosera-trap" || return 1
    fi
    
    print_message "Переходим в директорию my-drosera-trap..."
    cd my-drosera-trap
    check_result "Ошибка при переходе в директорию my-drosera-trap" || return 1
    
    return 0
}

configure_git() {
    print_step "Настройка Git"
    
    if ! command_exists git; then
        print_error "Git не установлен. Устанавливаем Git..."
        sudo apt-get update
        sudo apt-get install -y git
        check_result "Ошибка при установке Git" || return 1
    fi
    
    print_message "Настройка Git с использованием данных из конфигурационного файла..."
    git config --global user.email "$GITHUB_EMAIL"
    git config --global user.name "$GITHUB_USERNAME"
    check_result "Ошибка при настройке Git" || return 1
    
    print_message "Git успешно настроен с использованием данных из конфигурационного файла"
    git config --global --list
    
    return 0
}

initialize_trap() {
    print_step "Инициализация трапа"
    
    print_message "Инициализация трапа с использованием шаблона..."
    ${FORGE_BIN} init -t drosera-network/trap-foundry-template
    check_result "Ошибка при инициализации трапа" || return 1
    
    return 0
}

compile_trap() {
    print_step "Компиляция трапа"
    
    print_message "Установка зависимостей с помощью bun..."
    if ! command_exists bun; then
        print_error "Bun не установлен или не доступен в PATH"
        print_message "Переустанавливаем Bun..."
        
        curl -fsSL https://bun.sh/install | bash
        check_result "Ошибка при установке Bun" || return 1
        
        reload_env
    fi
    
    bun install
    check_result "Ошибка при установке зависимостей через bun" || return 1
    
    print_message "Компиляция контракта с помощью forge..."
    ${FORGE_BIN} build
    check_result "Ошибка при компиляции контракта" || {
        print_message "Компиляция завершилась с предупреждениями, но продолжаем работу"
        return 0
    }
    
    return 0
}

deploy_trap() {
    print_step "Деплой трапа"
    
    if ! command_exists drosera; then
        print_message "Drosera не найдена в PATH, проверяем локацию..."
        
        if [ -f "$HOME/.drosera/bin/drosera" ]; then
            print_message "Drosera найдена в $HOME/.drosera/bin"
            export PATH="$HOME/.drosera/bin:$PATH"
        else
            print_message "Drosera не найдена. Продолжаем, но деплой может быть невозможен"
        fi
    fi
    
    print_message "Деплой трапа с использованием данных из конфигурационного файла..."
    print_message "Будет использоваться приватный ключ и RPC URL из конфигурационного файла"
    
    DROSERA_PRIVATE_KEY=$EVM_PRIVATE_KEY drosera apply --eth-rpc-url $HOLESKY_RPC || true
    
    print_message "Деплой трапа завершен"
    print_message "ВАЖНО: После деплоя необходимо проверить статус трапа в панели управления Drosera"
    
    return 0
}

check_trap_and_fetch_blocks() {
    print_step "ШАГ 3: Проверка и настройка трапа"
    
    display_instructions_and_wait
    
    fetch_blocks
    
    print_step "Процесс проверки и настройки трапа завершен!"
    print_message "Перейдите в панель управления Drosera, чтобы проверить статус трапа"
    print_message "https://app.drosera.io/"
    
    return 0
}

display_instructions_and_wait() {
    print_step "Проверка Trap в панели управления Drosera"
    
    print_instruction "1. Перейдите на сайт Drosera: https://app.drosera.io/"
    print_instruction "2. Подключите ваш кошелек с адресом: ${EVM_PUBLIC_ADDRESS}"
    print_instruction "3. Нажмите на 'Traps Owned', чтобы увидеть ваши развернутые Traps"
    print_instruction "   или введите адрес вашего трапа в поиск"
    echo ""
    
    print_step "Bloom Boost трапа"
    
    print_instruction "1. Откройте ваш Trap в панели управления"
    print_instruction "2. Нажмите на 'Send Bloom Boost'"
    print_instruction "3. Отправьте немного Holesky ETH на ваш трап"
    print_instruction "   (Это необходимо для работы трапа, минимум 0.01 ETH)"
    echo ""
    
    print_input "После выполнения всех шагов выше нажмите Enter, чтобы продолжить..."
    read confirmation
}

fetch_blocks() {
    print_step "Загрузка блоков"
    
    if [ -d "$HOME/my-drosera-trap" ]; then
        print_message "Переходим в директорию $HOME/my-drosera-trap..."
        cd "$HOME/my-drosera-trap"
    elif [ -d "my-drosera-trap" ]; then
        print_message "Переходим в директорию my-drosera-trap..."
        cd "my-drosera-trap"
    else
        print_error "Директория my-drosera-trap не найдена"
        print_message "Команда drosera dryrun должна выполняться из директории трапа"
        print_input "Укажите путь к директории трапа: "
        read trap_dir
        
        if [ -d "$trap_dir" ]; then
            print_message "Переходим в директорию $trap_dir..."
            cd "$trap_dir"
        else
            print_error "Указанная директория не существует. Невозможно выполнить команду drosera dryrun"
            return 1
        fi
    fi
    
    if [ ! -f "drosera.toml" ]; then
        print_error "Файл drosera.toml не найден в текущей директории"
        print_message "Убедитесь, что вы находитесь в правильной директории трапа"
        return 1
    fi
    
    print_message "Текущая директория: $(pwd)"
    
    if ! command_exists drosera; then
        print_error "Drosera не найдена в PATH"
        
        if [ -f "$HOME/.drosera/bin/drosera" ]; then
            print_message "Drosera найдена в $HOME/.drosera/bin, добавляем в PATH..."
            export PATH="$HOME/.drosera/bin:$PATH"
        else
            print_error "Drosera не найдена. Невозможно выполнить команду drosera dryrun"
            return 1
        fi
    fi
    
    print_message "Запуск команды drosera dryrun с указанным RPC URL..."
    print_message "Эта команда загрузит блоки для вашего трапа"
    print_message "Процесс может занять некоторое время, пожалуйста, подождите..."
    
    drosera dryrun --eth-rpc-url $HOLESKY_RPC
    check_result "Возникла ошибка при выполнении drosera dryrun" || {
        print_message "Несмотря на ошибку, процесс может быть успешным."
        print_message "Проверьте вывод команды выше."
    }
    
    print_message "Загрузка блоков завершена!"
    print_message "Теперь вы можете проверить результаты в панели управления Drosera"
}

setup_operator() {
    print_step "ШАГ 4: Настройка оператора Drosera"
    
    configure_trap_whitelist
    
    install_operator_cli || {
        print_error "Не удалось установить CLI оператора"
        print_message "Это критическая ошибка. Прерываем выполнение шага."
        return 1
    }
    
    pull_operator_docker_image
    
    register_operator
    
    configure_firewall
    
    print_step "Настройка оператора Drosera завершена!"
    print_message "Оператор успешно настроен и готов к работе"
    print_message "Проверьте статус оператора в панели управления Drosera"
    print_message "https://app.drosera.io/"
    
    return 0
}

configure_trap_whitelist() {
    print_step "Настройка whitelist для трапа"
    
    print_message "Переходим в директорию my-drosera-trap..."
    if [ -d "$HOME/my-drosera-trap" ]; then
        cd "$HOME/my-drosera-trap"
    elif [ -d "my-drosera-trap" ]; then
        cd "my-drosera-trap"
    else
        print_error "Директория my-drosera-trap не найдена"
        print_message "Попробуем создать директорию и инициализировать трап в другой раз"
        print_message "Сейчас продолжим настройку оператора"
        return 1
    fi
    
    if [ ! -f "drosera.toml" ]; then
        print_error "Файл drosera.toml не найден в директории трапа"
        print_message "Возможно, трап не был корректно инициализирован"
        return 1
    fi
    
    print_message "Добавляем настройки whitelist в файл drosera.toml..."
    
    cp drosera.toml drosera.toml.bak
    print_message "Создана резервная копия файла конфигурации: drosera.toml.bak"
    
    trap_section=$(grep -o "\[traps\.[^]]*\]" drosera.toml | head -1)
    if [ -z "$trap_section" ]; then
        print_error "Не найдена секция трапа в файле drosera.toml"
        return 1
    fi
    
    print_message "Найдена секция трапа: $trap_section"
    
    tmp_file=$(mktemp)
    
    in_trap_section=false
    last_line_in_section=false
    
    while IFS= read -r line || [ -n "$line" ]; do
        if [[ "$line" == "$trap_section" ]]; then
            in_trap_section=true
            echo "$line" >> "$tmp_file"
        elif $in_trap_section && [[ "$line" =~ ^[[:space:]]*private_trap || "$line" =~ ^[[:space:]]*whitelist ]]; then
            continue
        elif $in_trap_section && [[ "$line" =~ ^\[ ]]; then
            echo "private_trap = true" >> "$tmp_file"
            echo "whitelist = [\"$EVM_PUBLIC_ADDRESS\"]" >> "$tmp_file"
            echo "" >> "$tmp_file"
            in_trap_section=false
            echo "$line" >> "$tmp_file"
        elif [ -z "$line" ] && $in_trap_section && ! $last_line_in_section; then
            echo "private_trap = true" >> "$tmp_file"
            echo "whitelist = [\"$EVM_PUBLIC_ADDRESS\"]" >> "$tmp_file"
            last_line_in_section=true
        else
            echo "$line" >> "$tmp_file"
        fi
    done < drosera.toml
    
    if $in_trap_section && ! $last_line_in_section; then
        echo "private_trap = true" >> "$tmp_file"
        echo "whitelist = [\"$EVM_PUBLIC_ADDRESS\"]" >> "$tmp_file"
    fi
    
    mv "$tmp_file" drosera.toml
    
    print_message "Настройки whitelist успешно добавлены в файл конфигурации"
    print_message "Используется адрес оператора: $EVM_PUBLIC_ADDRESS"
    
    if ! command_exists drosera; then
        print_message "Drosera не найдена в PATH, проверяем локацию..."
        if [ -f "$HOME/.drosera/bin/drosera" ]; then
            print_message "Drosera найдена в $HOME/.drosera/bin"
            export PATH="$HOME/.drosera/bin:$PATH"
        else
            print_message "Drosera не найдена. Продолжаем, но обновление конфигурации может быть невозможно"
        fi
    fi
    
    print_message "Обновляем конфигурацию трапа..."
    DROSERA_PRIVATE_KEY=$EVM_PRIVATE_KEY drosera apply --eth-rpc-url $HOLESKY_RPC || {
        print_error "Возникла ошибка при обновлении конфигурации трапа"
        print_message "Проверьте вывод команды выше на наличие ошибок"
        print_message "Продолжаем настройку оператора..."
    }
    
    print_message "Конфигурация трапа успешно обновлена"
    print_message "Теперь трап приватный с вашим адресом в whitelist"
    return 0
}

install_operator_cli() {
    print_step "Установка CLI оператора Drosera"
    
    print_message "Переходим в домашнюю директорию..."
    cd "$HOME"
    
    if command_exists drosera-operator; then
        print_message "CLI оператора Drosera уже установлен"
        drosera-operator --version
        print_input "Хотите переустановить CLI оператора? (y/n): "
        read reinstall_cli
        
        if [[ "$reinstall_cli" != "y" && "$reinstall_cli" != "Y" ]]; then
            print_message "Пропускаем установку CLI оператора"
            return 0
        fi
    fi
    
    print_message "Загрузка архива с CLI оператора..."
    curl -LO https://github.com/drosera-network/releases/releases/download/v1.16.2/drosera-operator-v1.16.2-x86_64-unknown-linux-gnu.tar.gz
    check_result "Ошибка при загрузке архива с CLI оператора" || return 1
    
    print_message "Распаковка архива..."
    tar -xvf drosera-operator-v1.16.2-x86_64-unknown-linux-gnu.tar.gz
    check_result "Ошибка при распаковке архива" || return 1
    
    print_message "Проверка работоспособности CLI оператора..."
    ./drosera-operator --version
    check_result "Ошибка при проверке версии CLI оператора" || return 1
    
    print_message "Копирование CLI оператора в /usr/bin для глобального доступа..."
    sudo cp drosera-operator /usr/bin
    check_result "Ошибка при копировании CLI оператора в /usr/bin" || return 1
    
    print_message "Проверка установки CLI оператора..."
    drosera-operator --version
    check_result "Ошибка при проверке установки CLI оператора" || {
        print_error "CLI оператора не был корректно установлен в PATH"
        print_message "Продолжаем настройку, но возможны проблемы"
    }
    
    print_message "CLI оператора Drosera успешно установлен"
    return 0
}

pull_operator_docker_image() {
    print_step "Загрузка Docker-образа оператора Drosera"
    
    if ! command_exists docker; then
        print_error "Docker не установлен. Невозможно загрузить образ оператора"
        print_message "Пожалуйста, установите Docker перед продолжением"
        return 1
    fi
    
    if sudo docker images | grep -q "ghcr.io/drosera-network/drosera-operator"; then
        print_message "Образ оператора Drosera уже загружен"
        return 0
    fi
    
    print_message "Загрузка образа оператора Drosera..."
    sudo docker pull ghcr.io/drosera-network/drosera-operator:latest
    check_result "Ошибка при загрузке образа оператора Drosera" || return 1
    
    print_message "Образ оператора Drosera успешно загружен"
    return 0
}

register_operator() {
    print_step "Регистрация оператора Drosera"
    
    if ! command_exists drosera-operator; then
        print_error "CLI оператора Drosera не установлен"
        print_message "Пожалуйста, установите CLI оператора перед регистрацией"
        return 1
    fi
    
    print_message "Регистрация оператора Drosera..."
    print_message "Используется приватный ключ из конфигурационного файла"
    drosera-operator register --eth-rpc-url $HOLESKY_RPC --eth-private-key $EVM_PRIVATE_KEY
    check_result "Ошибка при регистрации оператора Drosera" || {
        print_error "Возникла ошибка при регистрации оператора"
        print_message "Проверьте вывод команды выше на наличие ошибок"
        print_message "Продолжаем настройку..."
    }
    
    print_message "Оператор Drosera успешно зарегистрирован"
    return 0
}

configure_firewall() {
    print_step "Настройка брандмауэра"
    
    if ! command_exists ufw; then
        print_error "ufw не установлен. Невозможно настроить брандмауэр"
        print_message "Устанавливаем ufw..."
        sudo apt-get update
        sudo apt-get install -y ufw
        check_result "Ошибка при установке ufw" || return 1
    fi
    
    print_message "Разрешаем SSH-соединения..."
    sudo ufw allow ssh
    sudo ufw allow 22
    check_result "Ошибка при разрешении SSH-соединений" || return 1
    
    if sudo ufw status | grep -q "Status: active"; then
        print_message "Брандмауэр уже активирован"
    else
        print_message "Активация брандмауэра..."
        sudo ufw --force enable
        check_result "Ошибка при активации брандмауэра" || return 1
    fi
    
    print_message "Открываем порты для Drosera..."
    sudo ufw allow 31313/tcp
    sudo ufw allow 31314/tcp
    check_result "Ошибка при открытии портов для Drosera" || return 1
    
    print_message "Проверка статуса брандмауэра..."
    sudo ufw status
    
    print_message "Брандмауэр успешно настроен"
    return 0
}

setup_systemd_service() {
    print_step "ШАГ 5: Настройка системного сервиса Drosera оператора"
    
    create_systemd_service || {
        print_error "Не удалось создать файл сервиса systemd"
        return 1
    }
    
    start_systemd_service || {
        print_error "Не удалось запустить сервис systemd"
        return 1
    }
    
    display_additional_commands
    
    print_input "Хотите проверить состояние ноды? (y/n): "
    read check_health
    
    if [[ "$check_health" == "y" || "$check_health" == "Y" ]]; then
        check_node_health
    fi
    
    print_step "Настройка системного сервиса Drosera оператора завершена!"
    print_message "Оператор успешно настроен и запущен как системный сервис"
    print_message "Сервис настроен на автоматический запуск при перезагрузке сервера"
    print_message "Проверьте статус оператора в панели управления Drosera"
    print_message "https://app.drosera.io/"
    
    return 0
}

create_systemd_service() {
    print_step "Создание файла сервиса systemd для Drosera оператора"
    
    if ! command_exists drosera-operator; then
        print_error "CLI оператора Drosera не установлен"
        print_message "Пожалуйста, установите CLI оператора перед созданием сервиса"
        return 1
    fi
    
    DROSERA_OPERATOR_PATH=$(which drosera-operator)
    if [ -z "$DROSERA_OPERATOR_PATH" ]; then
        print_error "Не удалось определить путь к исполняемому файлу drosera-operator"
        print_message "Проверьте установку CLI оператора"
        return 1
    fi
    
    print_message "Создание файла сервиса systemd с использованием данных из конфигурационного файла..."
    print_message "Приватный ключ: $EVM_PRIVATE_KEY"
    print_message "IP-адрес сервера: $SERVER_IP"
    print_message "RPC URL: $HOLESKY_RPC"
    
    sudo tee /etc/systemd/system/drosera.service > /dev/null <<EOF
[Unit]
Description=drosera node service
After=network-online.target

[Service]
User=$USER
Restart=always
RestartSec=15
LimitNOFILE=65535
ExecStart=$DROSERA_OPERATOR_PATH node --db-file-path $HOME/.drosera.db --network-p2p-port 31313 --server-port 31314 \\
    --eth-rpc-url $HOLESKY_RPC \\
    --eth-backup-rpc-url https://1rpc.io/holesky \\
    --drosera-address 0xea08f7d533C2b9A62F40D5326214f39a8E3A32F8 \\
    --eth-private-key $EVM_PRIVATE_KEY \\
    --listen-address 0.0.0.0 \\
    --network-external-p2p-address $SERVER_IP \\
    --disable-dnr-confirmation true

[Install]
WantedBy=multi-user.target
EOF
    check_result "Ошибка при создании файла сервиса systemd" || return 1
    
    print_message "Файл сервиса systemd успешно создан в /etc/systemd/system/drosera.service"
    return 0
}

start_systemd_service() {
    print_step "Запуск сервиса Drosera оператора"
    
    print_message "Перезагрузка systemd..."
    sudo systemctl daemon-reload
    check_result "Ошибка при перезагрузке systemd" || return 1
    
    print_message "Включение автозапуска сервиса..."
    sudo systemctl enable drosera
    check_result "Ошибка при включении автозапуска сервиса" || return 1
    
    print_message "Запуск сервиса..."
    sudo systemctl start drosera
    check_result "Ошибка при запуске сервиса" || {
        print_error "Возникла ошибка при запуске сервиса. Проверяем статус..."
        sudo systemctl status drosera --no-pager
        return 1
    }
    
    print_message "Проверка статуса сервиса..."
    sudo systemctl status drosera --no-pager
    
    print_message "Сервис Drosera оператора успешно запущен!"
    return 0
}

check_node_health() {
    print_step "Проверка состояния ноды Drosera"
    
    print_message "Проверка журнала сервиса..."
    print_message "Для выхода из просмотра журнала нажмите Ctrl+C"
    print_message "Начинаем мониторинг журнала через 3 секунды..."
    
    sleep 3
    
    sudo journalctl -u drosera.service -f
    
    return 0
}

display_additional_commands() {
    print_step "Дополнительные команды для управления сервисом"
    
    print_instruction "Для остановки ноды используйте команду:"
    print_code "sudo systemctl stop drosera"
    
    print_instruction "Для перезапуска ноды используйте команду:"
    print_code "sudo systemctl restart drosera"
    
    print_instruction "Для просмотра журнала ноды используйте команду:"
    print_code "sudo journalctl -u drosera.service -f"
    
    print_message "ВНИМАНИЕ: Сообщение 'WARN drosera_services::network::service: Failed to gossip message: InsufficientPeers' не является ошибкой и может появляться в журнале"
    
    return 0
}

show_menu() {
    clear
    print_menu "========================================"
    print_menu "        DROSERA INSTALLATION MENU       "
    print_menu "========================================"
    print_menu ""
    print_menu " 1. Шаг 1: Установка пререквизитов"
    print_menu " 2. Шаг 2: Развертывание контракта и трапа"
    print_menu " 3. Шаг 3: Проверка и настройка трапа"
    print_menu " 4. Шаг 4: Настройка оператора"
    print_menu " 5. Шаг 5: Настройка системного сервиса"
    print_menu " 6. Выполнить все шаги последовательно"
    print_menu " 0. Выход"
    print_menu ""
    print_menu "========================================"
    print_input "Выберите опцию (0-6): "
}

run_all_steps() {
    print_step "Выполнение всех шагов установки Drosera последовательно"
    
    install_prerequisites || {
        print_error "Ошибка при выполнении шага 1: Установка пререквизитов"
        print_input "Хотите продолжить выполнение следующих шагов? (y/n): "
        read continue_after_step1
        if [[ "$continue_after_step1" != "y" && "$continue_after_step1" != "Y" ]]; then
            return 1
        fi
    }
    
    deploy_contract_and_trap || {
        print_error "Ошибка при выполнении шага 2: Развертывание контракта и трапа"
        print_input "Хотите продолжить выполнение следующих шагов? (y/n): "
        read continue_after_step2
        if [[ "$continue_after_step2" != "y" && "$continue_after_step2" != "Y" ]]; then
            return 1
        fi
    }
    
    check_trap_and_fetch_blocks || {
        print_error "Ошибка при выполнении шага 3: Проверка и настройка трапа"
        print_input "Хотите продолжить выполнение следующих шагов? (y/n): "
        read continue_after_step3
        if [[ "$continue_after_step3" != "y" && "$continue_after_step3" != "Y" ]]; then
            return 1
        fi
    }
    
    setup_operator || {
        print_error "Ошибка при выполнении шага 4: Настройка оператора"
        print_input "Хотите продолжить выполнение следующих шагов? (y/n): "
        read continue_after_step4
        if [[ "$continue_after_step4" != "y" && "$continue_after_step4" != "Y" ]]; then
            return 1
        fi
    }
    
    setup_systemd_service || {
        print_error "Ошибка при выполнении шага 5: Настройка системного сервиса"
        return 1
    }
    
    print_step "Все шаги установки Drosera успешно выполнены!"
    print_message "Drosera успешно установлена и настроена на вашем сервере"
    print_message "Проверьте статус в панели управления Drosera:"
    print_message "https://app.drosera.io/"
    
    return 0
}

main() {
    read_config || {
        print_error "Ошибка при чтении конфигурационного файла. Установка невозможна."
        exit 1
    }
    
    while true; do
        show_menu
        read choice
        
        case $choice in
            1)
                install_prerequisites
                print_input "Нажмите Enter для возврата в меню..."
                read
                ;;
            2)
                deploy_contract_and_trap
                print_input "Нажмите Enter для возврата в меню..."
                read
                ;;
            3)
                check_trap_and_fetch_blocks
                print_input "Нажмите Enter для возврата в меню..."
                read
                ;;
            4)
                setup_operator
                print_input "Нажмите Enter для возврата в меню..."
                read
                ;;
            5)
                setup_systemd_service
                print_input "Нажмите Enter для возврата в меню..."
                read
                ;;
            6)
                run_all_steps
                print_input "Нажмите Enter для возврата в меню..."
                read
                ;;
            0)
                print_message "Выход из скрипта установки Drosera"
                exit 0
                ;;
            *)
                print_error "Неверный выбор. Пожалуйста, выберите опцию от 0 до 6."
                print_input "Нажмите Enter для продолжения..."
                read
                ;;
        esac
    done
}

main
