/*
 * 接收侧：CRC 校验、按序交付、纯 ACK 组帧。
 */

#include <string.h>
#include "protocol.h"
#include "datalink.h"

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

/*
 * 返回值：-1 非法帧；0 纯 ACK；1 按序 DATA；2 失序 DATA（不交付载荷）。
 */
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
        dbg_event("out-of-order frame: got seq=%u, expected %u, discarded payload\n",
                  (unsigned)f->seq, (unsigned)fe);
        return 2;
    }

    memcpy(data_out, f->data, PKT_LEN);
    *data_len = PKT_LEN;
    frame_expected = (unsigned char)((fe + 1) % (MAX_SEQ + 1));
    return 1;
}
