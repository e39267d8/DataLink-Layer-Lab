/*
 * 接收侧与纯 ACK —— 尹浩铭主责；本文件提供与 datalink.c 的约定接口。
 * 张恒基在 FRAME_RECEIVED / ACK_TIMEOUT 中只调用下列函数，不重复实现 CRC 细节。
 */

#include <string.h>
#include "protocol.h"
#include "datalink.h"

/* 接收端按序期望的下一 DATA 序号（用于捎带 ACK 与纯 ACK 的 ack 字段） */
static unsigned char frame_expected;

unsigned char dl_get_frame_expected(void)
{
    return frame_expected;
}

void send_pure_ack(unsigned char ack_seq)
{
    unsigned char buf[8];

    buf[0] = (unsigned char)FRAME_ACK;
    buf[1] = 0U;
    buf[2] = ack_seq;
    {
        unsigned int cs = crc32(buf, FRAME_HDR_LEN);
        memcpy(buf + FRAME_HDR_LEN, &cs, sizeof(cs));
    }
    send_frame(buf, FRAME_HDR_LEN + (int)sizeof(unsigned int));
    dbg_event("sent pure ACK seq=%u\n", (unsigned)ack_seq);
}

int validate_and_process_frame(unsigned char *frame, int len, unsigned int *ack_seq,
    unsigned char *data_out, int *data_len)
{
    struct frame *f;
    unsigned char fe;

    if (ack_seq)
        *ack_seq = 0U;
    if (data_len)
        *data_len = 0;

    if (len < FRAME_HDR_LEN + (int)sizeof(unsigned int)) {
        dbg_event("too short frame (%d bytes, need >= %d), dropped\n",
                  len, FRAME_HDR_LEN + (int)sizeof(unsigned int));
        return -1;
    }

    if (crc32(frame, (unsigned int)len) != 0) {
        dbg_event("CRC-32 mismatch, frame dropped\n");
        return -1;
    }

    f = (struct frame *)frame;

    if (f->kind == FRAME_ACK) {
        *ack_seq = f->ack;
        return 0;
    }

    if (f->kind != FRAME_DATA) {
        dbg_event("unknown frame kind %u, dropped\n", (unsigned)f->kind);
        return -1;
    }

    if (len < FRAME_HDR_LEN + PKT_LEN + (int)sizeof(unsigned int)) {
        dbg_event("data frame too short (%d bytes), dropped\n", len);
        return -1;
    }

    *ack_seq = f->ack;

    fe = frame_expected;
    if (f->seq != fe) {
        /* GBN：非期望序号，不交付网络层；对端捎带的 ack 仍由调用方处理 */
        dbg_event("out-of-order frame: got seq=%u, expected %u, discarded payload\n",
                  (unsigned)f->seq, (unsigned)fe);
        return 2;
    }

    memcpy(data_out, f->data, PKT_LEN);
    *data_len = PKT_LEN;
    frame_expected = (unsigned char)((fe + 1) % (MAX_SEQ + 1));
    return 1;
}
