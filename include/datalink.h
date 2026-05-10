#ifndef DATALINK_H
#define DATALINK_H

/*
 * 自定义数据链路层类型与常量 —— 对应《计算机网络实验一》
 * 「7.2 协议设计和程序总体设计」：帧字段、窗口与状态由组内定义。
 * 物理层/网络层接口与事件定义见 protocol.h（指导书第 8 节）。
 */

#include "protocol.h"

/* 帧类型（可与教材 ACK/NAK/DATA 命名一致，按需扩展） */
#define FRAME_DATA 1
#define FRAME_ACK  2
#define FRAME_NAK  3

/*
 * 载荷长度：网络层分组固定为 PKT_LEN（指导书 8.6，一般为 256 字节）。
 * 一帧在内存中通常为「首部字段 + data[PKT_LEN]」，再在发送时追加 4 字节 CRC
 *（指导书 8.9：*(unsigned int *)(p + len) = crc32(p, len)；整帧校验用 crc32(p, len+4)==0）。
 *
 * DATA 帧（字段顺序可由组内约定，以下为一种与教材示意图一致的布局）：
 * +=========+========+========+===============+========+
 * | KIND(1) | SEQ(1) | ACK(1) | DATA(PKT_LEN) | CRC(4) |
 * +=========+========+========+===============+========+
 *
 * ACK / NAK 控制帧（仅示意，实际长度由 send_frame 的 len 决定）：
 * +=========+========+========+
 * | KIND(1) | ACK(1) | CRC(4) |
 * +=========+========+========+
 */

struct frame {
    unsigned char kind;
    unsigned char seq;
    unsigned char ack;
    unsigned char data[PKT_LEN];
};

#endif /* DATALINK_H */
