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
    la      t0, virtio_req_hdr
    addi    t0, s1, 48           # адрес дескриптора 2
    lb      a5, 0(t0)      # Читаем статус из дескриптора 2
    bnez    a5, virtio_request_fail

    li      a0, 0                # Успех
    ret

virtio_request_fail:
    li      a0, -1               # Ошибка операции
    ret

