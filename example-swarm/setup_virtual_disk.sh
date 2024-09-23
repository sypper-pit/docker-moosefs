#!/bin/bash

# Скрипт для автоматического создания и настройки виртуального жесткого диска для MooseFS

# Функция для вывода сообщений
echo_info() {
    echo -e "\e[32m[INFO]\e[0m $1"
}

echo_warning() {
    echo -e "\e[33m[WARNING]\e[0m $1"
}

echo_error() {
    echo -e "\e[31m[ERROR]\e[0m $1"
}

# Проверка, выполняется ли скрипт с правами root
if [[ $EUID -ne 0 ]]; then
   echo_error "Этот скрипт должен быть запущен с правами суперпользователя (sudo)."
   exit 1
fi

# Шаг 1: Запрос объема виртуального диска у пользователя
read -p "Введите объем виртуального диска (например, 30G, 500M): " DISK_SIZE

# Проверка корректности ввода
if ! [[ "$DISK_SIZE" =~ ^[0-9]+[MG]$ ]]; then
    echo_error "Некорректный формат объема. Используйте числа с суффиксами G или M (например, 30G)."
    exit 1
fi

# Шаг 2: Создание необходимых директорий
echo_info "Создание необходимых директорий в /srv/moosefs и /mnt/moosefs..."
mkdir -p /srv/moosefs/master
mkdir -p /srv/moosefs/metaserver
mkdir -p /srv/moosefs/chunkserver
mkdir -p /srv/moosefs/client
mkdir -p /srv/moosefs/metalogger
mkdir -p /mnt/moosefs/virtual_disk

# Шаг 3: Создание файла виртуального диска
IMAGE_PATH="/srv/moosefs/virtual_disk.img"

if [[ -f "$IMAGE_PATH" ]]; then
    echo_warning "Файл $IMAGE_PATH уже существует."
    read -p "Хотите перезаписать существующий файл? Все данные на нем будут потеряны! (y/n): " CONFIRM
    if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
        echo_info "Отмена операции."
        exit 0
    fi
    rm -f "$IMAGE_PATH"
fi

echo_info "Создание файла виртуального диска размером $DISK_SIZE..."
fallocate -l "$DISK_SIZE" "$IMAGE_PATH" 2>/dev/null
if [[ $? -ne 0 ]]; then
    echo_warning "fallocate не удалось. Используем dd для создания файла."
    dd if=/dev/zero of="$IMAGE_PATH" bs=1M count=$(echo "$DISK_SIZE" | grep -oP '^\d+')000 <<< "$(echo "$DISK_SIZE" | grep -oP '[MG]')"
    if [[ $? -ne 0 ]]; then
        echo_error "Не удалось создать файл виртуального диска с помощью dd."
        exit 1
    fi
fi

# Шаг 4: Присвоение свободного циклического устройства
echo_info "Поиск свободного циклического устройства..."
FREE_LOOP=$(losetup -f)

if [[ -z "$FREE_LOOP" ]]; then
    echo_error "Не удалось найти свободное циклическое устройство."
    exit 1
fi

echo_info "Присвоение $IMAGE_PATH к $FREE_LOOP..."
losetup "$FREE_LOOP" "$IMAGE_PATH"

if [[ $? -ne 0 ]]; then
    echo_error "Не удалось присвоить циклическое устройство."
    exit 1
fi

# Шаг 5: Создание файловой системы
echo_info "Создание файловой системы ext4 на $FREE_LOOP..."
mkfs.ext4 "$FREE_LOOP"

if [[ $? -ne 0 ]]; then
    echo_error "Не удалось создать файловую систему на $FREE_LOOP."
    # Отвязка устройства перед выходом
    losetup -d "$FREE_LOOP"
    exit 1
fi

# Шаг 6: Монтирование устройства
echo_info "Монтирование $FREE_LOOP в /mnt/moosefs/virtual_disk..."
mount "$FREE_LOOP" /mnt/moosefs/virtual_disk

if [[ $? -ne 0 ]]; then
    echo_error "Не удалось смонтировать $FREE_LOOP."
    # Отвязка устройства перед выходом
    losetup -d "$FREE_LOOP"
    exit 1
fi

# Шаг 7: Получение UUID устройства
UUID=$(blkid -s UUID -o value "$FREE_LOOP")
if [[ -z "$UUID" ]]; then
    echo_error "Не удалось получить UUID для $FREE_LOOP."
    # Отмонтировать и отвязать устройство перед выходом
    umount /mnt/moosefs/virtual_disk
    losetup -d "$FREE_LOOP"
    exit 1
fi

# Шаг 8: Добавление записи в /etc/fstab
FSTAB_ENTRY="UUID=$UUID /mnt/moosefs/virtual_disk ext4 defaults 0 2"

# Проверка, существует ли уже такая запись
grep -qs "$UUID" /etc/fstab
if [[ $? -eq 0 ]]; then
    echo_warning "Запись для UUID=$UUID уже существует в /etc/fstab."
else
    echo_info "Добавление записи в /etc/fstab для автоматического монтирования..."
    echo "$FSTAB_ENTRY" >> /etc/fstab
    if [[ $? -ne 0 ]]; then
        echo_error "Не удалось добавить запись в /etc/fstab."
        # Отмонтировать и отвязать устройство перед выходом
        umount /mnt/moosefs/virtual_disk
        losetup -d "$FREE_LOOP"
        exit 1
    fi
fi

# Применение изменений без перезагрузки
echo_info "Применение изменений в /etc/fstab..."
mount -a

if [[ $? -ne 0 ]]; then
    echo_error "Ошибка при монтировании файловых систем из /etc/fstab."
    exit 1
fi

# Шаг 9: Проверка точки монтирования
echo_info "Проверка точки монтирования..."
if mountpoint -q /mnt/moosefs/virtual_disk; then
    echo_info "Виртуальный диск успешно смонтирован в /mnt/moosefs/virtual_disk."
else
    echo_error "Точка монтирования /mnt/moosefs/virtual_disk не является смонтированной."
    exit 1
fi

echo_info "Автоматизация завершена успешно!"

# Опционально: Интеграция с MooseFS (можно добавить дополнительные шаги здесь)
