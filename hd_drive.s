.section .text
.global virtio_blk_init

# Функция virtio_blk_init:
# Инициализирует virtio‑блочное устройство через MMIO.
#
# Используемые MMIO‑регистры (относительно базового адреса):
#  0x000: magic value (ожидается 0x74726976, "virt")
#  0x004: версия (ожидается 2)
#  0x008: device id (для virtio‑blk должно быть 2)
#
#  0x010: device_features
#  0x014: device_features_sel
#
#  0x020: driver_features
#  0x024: driver_features_sel
#
#  0x070: статус устройства.
#
virtio_blk_init:
    # t0 = базовый адрес virtio‑устройства (MMIO)
    li      t0, 0x10001000

    # Проверяем magic value (смещение 0x000)
    lw      t1, 0(t0)           # t1 = *(uint32_t*)(base + 0)
    li      t2, 0x74726976      # Ожидаемое значение "virt"
    bne     t1, t2, virtio_fail

    # Проверяем версию (смещение 0x004)
    lw      t1, 4(t0)           # t1 = *(uint32_t*)(base + 4)
    li      t2, 1               # Ожидаем версия 2 /* version 1.1 */
    bne     t1, t2, virtio_fail

    # Проверяем device id (смещение 0x008)
    lw      t1, 8(t0)           # t1 = device id
    li      t2, 2               # Для virtio‑blk device id должен быть 2
    bne     t1, t2, virtio_fail

    # Устанавливаем статус: ACKNOWLEDGE (бит 0), DRIVER (бит 1)
    li      t1, 3              # статус = 1 (ACKNOWLEDGE)
    sw      t1, 0x70(t0)       # Записываем в статус

    # Согласование фичей:
    # Сначала выбираем device_features_sel = 0 и читаем device_features.
    li      t2, 0
    sw      t2, 0x14(t0)       # Устанавливаем device_features_sel = 0
    lw      t1, 0x10(t0)       # t1 = device_features (от устройства)

    # Здесь можно проанализировать t1 и выбрать нужные фичи.
    # Для минимальной поддержки выбираем driver_features = 0.
    li      t3, 0             # t3 = выбранные фичи (0)

    # Устанавливаем driver_features_sel = 0 и записываем driver_features.
    li      t2, 0
    sw      t2, 0x24(t0)       # driver_features_sel = 0
    sw      t3, 0x20(t0)       # Записываем выбранные фичи

    # Обновляем статус: добавляем FEATURES_OK (бит 3).
    # Текущий статус был 3, добавляем 4, получаем 7.
    li      t1, 0xF
    sw      t1, 0x70(t0)

    # Возвращаем 0 (успех)
    li      a3, 0
    ret

virtio_fail:
    # Если ошибка инициализации, возвращаем -1.
    li      a3, -1
    ret

