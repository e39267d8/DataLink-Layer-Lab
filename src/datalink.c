/*
 * 数据链路层主控 —— 张恒基：事件循环 + GBN 发送侧状态机。
 * 接收校验、纯 ACK 组帧见 datalink_recv.c（尹浩铭接口）。
 */

#include <stdio.h>
#include <string.h>
#include "protocol.h"
#include "datalink.h"

/* ---------- 发送窗口状态 ---------- */
static unsigned char ack_expected;
static unsigned char next_frame_to_send;
static unsigned char frame_buffer[NR_BUFS][MAX_FRAME_BYTES];
static int frame_saved_len[NR_BUFS];

/* 物理层发送队列低于阈值后为 1；send_frame 后置 0，等待 PHYSICAL_LAYER_READY */
static int phl_ready = 1;

static unsigned nbuffered(void)
{
    unsigned M = (unsigned)(MAX_SEQ + 1);
    return (unsigned)((next_frame_to_send + M - ack_expected) % M);
}

static unsigned char inc_seq(unsigned char s)
{
    return (unsigned char)((s + 1) % (MAX_SEQ + 1));
}

void update_ack_received(unsigned char ack_seq)
{
    unsigned M = (unsigned)(MAX_SEQ + 1);
    unsigned w = (unsigned)((next_frame_to_send + M - ack_expected) % M);
    unsigned d = (unsigned)((ack_seq + M - ack_expected) % M);

    if (d == 0U || d > w)
        return;

    ack_expected = ack_seq;
    stop_timer(DATA_TIMER_ID);
    if (ack_expected != next_frame_to_send) {
        /* start_timer: 实际超时发生在物理层队列排空折算时间之后 + timeout_ms，
         * 与指导书 8.10 及本仓库 protocol.c 中 start_timer 实现一致。 */
        start_timer(DATA_TIMER_ID, DATA_TIMEOUT_MS);
    }
}

static void send_one_data_frame(void)
{
    unsigned char tx[MAX_FRAME_BYTES];
    unsigned int crc;
    int idx;
    int wire_len = FRAME_HDR_LEN + PKT_LEN + (int)sizeof(unsigned int);
    if (nbuffered() >= (unsigned)WINDOW_SIZE)
        return;

    tx[0] = FRAME_DATA;
    tx[1] = next_frame_to_send;
    tx[2] = dl_get_frame_expected();
    if (get_packet(tx + FRAME_HDR_LEN) != PKT_LEN)
        return;

    crc = crc32(tx, (unsigned int)(FRAME_HDR_LEN + PKT_LEN));
    memcpy(tx + FRAME_HDR_LEN + PKT_LEN, &crc, sizeof(crc));

    idx = next_frame_to_send % NR_BUFS;
    memcpy(frame_buffer[idx], tx, (size_t)wire_len);
    frame_saved_len[idx] = wire_len;

    send_frame(tx, wire_len);
    phl_ready = 0;
    next_frame_to_send = inc_seq(next_frame_to_send);

    stop_timer(DATA_TIMER_ID);
    if (ack_expected != next_frame_to_send)
        start_timer(DATA_TIMER_ID, DATA_TIMEOUT_MS);
}

static void resend_window(void)
{
    unsigned char s = ack_expected;

    while (s != next_frame_to_send) {
        int idx = s % NR_BUFS;
        send_frame(frame_buffer[idx], frame_saved_len[idx]);
        s = inc_seq(s);
    }
    phl_ready = 0;
    stop_timer(DATA_TIMER_ID);
    if (ack_expected != next_frame_to_send)
        start_timer(DATA_TIMER_ID, DATA_TIMEOUT_MS);
}

static void refresh_network_layer_gate(void)
{
    /* 与 protocol.c 中 PHL_SQ_LEVEL(50) 一致；队列已排空则视为可发，避免漏掉 READY 事件 */
    if (phl_sq_len() < 50)
        phl_ready = 1;

    if (nbuffered() < (unsigned)WINDOW_SIZE && phl_ready)
        enable_network_layer();
    else
        disable_network_layer();
}

int main(int argc, char **argv)
{
    int event, arg;
    unsigned char rxbuf[512];

    protocol_init(argc, argv);
    lprintf("datalink GBN build: " __DATE__ " " __TIME__ "\n");

    ack_expected = 0;
    next_frame_to_send = 0;

    disable_network_layer();

    for (;;) {
        event = wait_for_event(&arg);

        switch (event) {
        case NETWORK_LAYER_READY:
            send_one_data_frame();
            break;

        case PHYSICAL_LAYER_READY:
            phl_ready = 1;
            break;

        case FRAME_RECEIVED: {
            int len, rc;
            unsigned int ack_seq = 0;
            unsigned char data_out[PKT_LEN];
            int data_len = 0;

            len = recv_frame(rxbuf, (int)sizeof(rxbuf));
            rc = validate_and_process_frame(rxbuf, len, &ack_seq, data_out, &data_len);
            if (rc < 0) {
                dbg_warning("CRC error or bad frame, dropped\n");
                break;
            }
            update_ack_received((unsigned char)ack_seq);
            if (rc == 1)
                put_packet(data_out, data_len);
            if (rc == 1 || rc == 2)
                start_ack_timer(ACK_TIMEOUT_MS);
            break;
        }

        case DATA_TIMEOUT:
            (void)arg;
            resend_window();
            break;

        case ACK_TIMEOUT:
            send_pure_ack(dl_get_frame_expected());
            phl_ready = 0;
            stop_ack_timer();
            break;

        default:
            break;
        }

        refresh_network_layer_gate();
    }

    /* not reached */
}
