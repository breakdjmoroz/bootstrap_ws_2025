    .section .bss
    .align 4096
virtqueue_space:
    .space 4096           # Область для virtqueue (таблица дескрипторов, avail и used кольца)

    .section .bss
    .align 16
virtio_req_hdr:
    .space 16             # Заголовок запроса (struct virtio_blk_req: type, reserved, sector)
data_buffer:
    .space 512            # Буфер для данных (обычно 512 байт)
status_byte:
    .space 1              # 1 байт для статуса операции

    .section .data
VIRTQ_DESC_F_NEXT:
    .word 1
VIRTQ_DESC_F_WRITE:
    .word 2

    .section .text
    .global virtio_blk_init
    .global virtqueue_init
    .global virtio_blk_read_request

#------------------------------------------------------------
# virtio_blk_init:
# Инициализирует virtio‑блочное устройство через MMIO.
# Используемые регистры (от базового адреса 0x10001000):
#   0x000: magic value (ожидается 0x74726976, "virt")
#   0x004: версия (ожидается 2)
#   0x008: device id (для virtio‑blk должно быть 2)
#
#   0x010: device_features
#   0x014: device_features_sel
#
#   0x020: driver_features
#   0x024: driver_features_sel
#
#   0x070: статус устройства.
virtio_blk_init:
    li      t0, 0x10001000       # базовый адрес virtio-устройства

    # Проверяем magic value
    lw      t1, 0(t0)           # Читаем magic value
    li      t2, 0x74726976      # Ожидаем "virt"
    bne     t1, t2, virtio_fail

    # Проверяем версию
    lw      t1, 4(t0)           # Читаем версию
    li      t2, 1
    bne     t1, t2, virtio_fail

    # Проверяем device id
    lw      t1, 8(t0)           # Читаем device id
    li      t2, 2               # Для virtio‑blk должно быть 2
    bne     t1, t2, virtio_fail

    # Устанавливаем статус: ACKNOWLEDGE
    li      t1, 1
    sw      t1, 0x70(t0)
    # Устанавливаем статус: DRIVER (итоговый статус 1|2 = 3)
    li      t1, 3
    sw      t1, 0x70(t0)

    # Согласование фич:
    li      t2, 0
    sw      t2, 0x14(t0)       # device_features_sel = 0
    lw      t1, 0x10(t0)       # Читаем device_features
    li      t3, 0             # Выбираем driver_features = 0
    li      t2, 0
    sw      t2, 0x24(t0)       # driver_features_sel = 0
    sw      t3, 0x20(t0)       # Записываем выбранные фичи

    # Обновляем статус: FEATURES_OK (добавляем бит 2, итог 7)
    li      t1, 7
    sw      t1, 0x70(t0)

    li      a3, 0             # Возвращаем успех (0)
    ret

virtio_fail:
    li      a3, -1
    ret

#------------------------------------------------------------
# virtqueue_init:
# Настраивает virtqueue 0, выделяя память для дескрипторов, avail и used колец.
# Используемые MMIO-регистры (от 0x10001000):
#   0x30: Queue Select (16-бит)
#   0x34: Queue Size (16-бит)
#   0x3c: Queue Align (32-бит) – обычно 4096
#   0x40: Queue Pfn (32-бит) – физический номер страницы для очереди
virtqueue_init:
    li      t0, 0x10001000

    # Выбираем очередь 0
    li      t1, 0
    sw      t1, 0x30(t0)       # queue_select = 0

    # Читаем queue_size (смещение 0x38)
    lw      t2, 0x34(t0)
    beqz    t2, virtqueue_fail2
    li      t3, 8              # Наше число дескрипторов: 8
    blt     t2, t3, virtqueue_fail2

    # Устанавливаем queue_align = 4096
    li      t4, 4096
    sw      t4, 0x3c(t0)

    # Вычисляем физический номер страницы для virtqueue_space.
    la      t5, virtqueue_space
    srli    t6, t5, 12
    sw      t6, 0x40(t0)

    li      a3, 0
    ret

virtqueue_fail2:
    li      a3, -1
    ret
#------------------------------------------------------------
# virtio_blk_read_request:
# Формирует запрос virtio‑blk для чтения блока (номер сектора передаётся в a0),
# создаёт цепочку из 3 дескрипторов (для заголовка, данных и статуса),
# добавляет индекс 0 в avail ring и уведомляет устройство.
# Затем функция ожидает появления результата в used ring (предполагается, что used ring
# расположен по смещению 256 от начала virtqueue_space), проверяет статус операции и возвращает 0
# при успехе или -1 при ошибке.
virtio_blk_read_request:
    # Сохраняем базовый адрес virtio‑устройства (MMIO) в s0.
    li      s0, 0x10001000

    # 1. Формирование структуры запроса в virtio_req_hdr.
    la      t0, virtio_req_hdr
    li      t1, 0                # VIRTIO_BLK_T_IN = 0 (чтение)
    sw      t1, 0(t0)            # type
    sw      zero, 4(t0)          # reserved = 0
    mv      t2, a0               # номер сектора передаётся в a0
    sd      t2, 8(t0)            # sector (8 байт)

    # 2. Формирование цепочки дескрипторов virtqueue.
    la      s1, virtqueue_space  # база virtqueue
    # Дескриптор 0: для заголовка запроса.
    la      t0, virtio_req_hdr
    sd      t0, 0(s1)            # descriptor[0].addr = virtio_req_hdr
    li      t0, 16
    sw      t0, 8(s1)            # descriptor[0].len = 16
    li      t0, 1                # флаг NEXT
    sh      t0, 12(s1)           # descriptor[0].flags = 1
    li      t0, 1
    sh      t0, 14(s1)           # descriptor[0].next = 1

    # Дескриптор 1: для буфера данных.
    addi    t0, s1, 16           # адрес дескриптора 1
    la      t1, data_buffer
    sd      t1, 0(t0)            # descriptor[1].addr = data_buffer
    li      t1, 512
    sw      t1, 8(t0)            # descriptor[1].len = 512
    li      t1, 3                # флаги: NEXT | WRITE = 1|2 = 3
    sh      t1, 12(t0)           # descriptor[1].flags = 3
    li      t1, 2
    sh      t1, 14(t0)           # descriptor[1].next = 2

    # Дескриптор 2: для статуса.
    addi    t0, s1, 32           # адрес дескриптора 2
    la      t1, status_byte
    sd      t1, 0(t0)            # descriptor[2].addr = status_byte
    li      t1, 1
    sw      t1, 8(t0)            # descriptor[2].len = 1
    li      t1, 2                # флаг WRITE = 2
    sh      t1, 12(t0)           # descriptor[2].flags = 2
    li      t1, 0
    sh      t1, 14(t0)           # descriptor[2].next = 0

    # 3. Добавление запроса в avail ring.
    # Предполагается, что таблица дескрипторов (8 дескрипторов по 16 байт) занимает 128 байт,
    # avail ring начинается по смещению 128 от начала virtqueue_space.
    li      t0, 128
    add     t0, t0, s1           # t0 = адрес avail ring
    # Формат avail ring: 16-бит flags (offset 0), 16-бит idx (offset 2),
    # далее массив 16-бит номеров дескрипторов, начиная с offset 4.
    li      t1, 0
    sh      t1, 0(t0)            # avail.flags = 0
    li      t1, 1
    sh      t1, 2(t0)            # avail.idx = 1 (один элемент в очереди)
    li      t1, 0
    sh      t1, 4(t0)            # avail.ring[0] = 0 (начинается с дескриптора 0)

    # 4. Уведомление устройства.
    # Запись в регистр queue_notify (смещение 0x50) уведомляет устройство о новом запросе.
    li      t0, 0                # очередь 0
    sw      t0, 0x50(s0)

    # 5. Ожидаем ответа устройства, опрашивая used ring.
    # Предположим, что used ring находится по смещению 256 от начала virtqueue_space.
    li      a7, 256
    add     a7, s1, a7           # t7 = адрес used ring
poll_used:
    lh      a6, 2(a7)            # Читаем 16-битное поле used.idx по offset 2
    beqz    a6, poll_used        # Если used.idx == 0, ждем

    # 6. Проверяем статус операции (status_byte).
    lb      a5, status_byte      # Читаем статус из дескриптора 2
    bnez    a5, virtio_request_fail

    li      a3, 0                # Успех
    ret

virtio_request_fail:
    li      a3, -1               # Ошибка операции
    ret
