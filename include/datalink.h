#ifndef DATALINK_H
#define DATALINK_H

#include "protocol.h"

#define FRAME_DATA 1
#define FRAME_ACK  2
#define FRAME_NAK  3

#define MAX_SEQ       255
#define NR_BUFS       256
#define WINDOW_SIZE   5

#define DATA_TIMER_ID 0
#define DATA_TIMEOUT_MS 600
#define ACK_TIMEOUT_MS  50

#define FRAME_HDR_LEN   3
#define MAX_FRAME_BYTES (FRAME_HDR_LEN + PKT_LEN + 4)

struct frame {
    unsigned char kind;
    unsigned char seq;
    unsigned char ack;
    unsigned char data[PKT_LEN];
};

void update_ack_received(unsigned char ack_seq);

unsigned char dl_get_frame_expected(void);

int validate_and_process_frame(unsigned char *frame, int len, unsigned int *ack_seq,
    unsigned char *data_out, int *data_len);

void send_pure_ack(unsigned char ack_seq);

#endif
