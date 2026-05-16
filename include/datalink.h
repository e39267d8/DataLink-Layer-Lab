#ifndef DATALINK_H
#define DATALINK_H

/*
 * 数据链路层：帧布局、窗口常量、与 recv 模块的接口约定。
 * 物理层/网络层/事件见 protocol.h。
 */

#include "protocol.h"

#define FRAME_DATA 1
#define FRAME_ACK  2
#define FRAME_NAK  3

/*
 * 序号空间与发送窗口（与实验报告 11.3、张恒基分工文档一致）。
 * seq/ack 字段为 1 字节，使用完整 0..255 空间；WINDOW_SIZE 在 BDP 基础上略放大以缓解对称死锁。
 * 较大的序号空间能避免误码重传时旧帧在物理层队列中滞留、序号过早回绕后被误收。
 */
#define MAX_SEQ       255
#define NR_BUFS       256
/*
 * WINDOW_SIZE：按「字节口径」带宽时延积估算——
 * RTT = 2×270 ms = 540 ms，8000 bps × 0.54 s = 4320 bit = 540 字节；
 * 若整帧约 260 字节（256 载荷 + 帧头 + CRC），540/260 ≈ 2.08，向上取 3。
 * 教材比特公式 (2*t_p+t_tx)/t_tx 亦可得约 3.05；为缓解全双工对称死锁，运行取 5。
 */
#define WINDOW_SIZE   5

/* 定时器：数据重传使用单一编号 0（须 < ACK_TIMER，见 protocol.c） */
#define DATA_TIMER_ID 0

/*
 * DATA_TIMEOUT_MS：正常应略大于 RTT + 处理余量；RTT≈540 ms 时取 600 ms。
 * 库中 start_timer 另含 phl_sq_len 排队项，见 protocol.c。
 */
#define DATA_TIMEOUT_MS 600
/* ACK 搭载：缩短空等，尽快释放对端发送窗口 */
#define ACK_TIMEOUT_MS  50

/* 帧首部长度：kind(1) + seq(1) + ack(1) */
#define FRAME_HDR_LEN   3

/* 线路上最大帧长：首部 + PKT_LEN + CRC32 */
#define MAX_FRAME_BYTES (FRAME_HDR_LEN + PKT_LEN + 4)

struct frame {
    unsigned char kind;
    unsigned char seq;
    unsigned char ack;
    unsigned char data[PKT_LEN];
};

/* 发送侧：由张恒基在 datalink.c 实现 */
void update_ack_received(unsigned char ack_seq);

/* 接收侧：由尹浩铭维护 datalink_recv.c；供组帧时捎带 ACK */
unsigned char dl_get_frame_expected(void);

/*
 * 校验并处理一帧（尹浩铭主责实现）。
 * 返回值：-1 CRC/长度非法；0 纯 ACK 控制帧；1 按序 DATA 已写入 data_out；
 *         2 失序或重复 DATA（不交付载荷，仍带出对端捎带的 ack_seq）。
 */
int validate_and_process_frame(unsigned char *frame, int len, unsigned int *ack_seq,
    unsigned char *data_out, int *data_len);

/* 纯 ACK（尹浩铭主责）；由张恒基在 ACK_TIMEOUT 分支调用 */
void send_pure_ack(unsigned char ack_seq);

#endif /* DATALINK_H */
