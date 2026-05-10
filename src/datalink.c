#include <stdio.h>
#include <string.h>
#include "protocol.h"
#include "datalink.h"

/*
 * 主控流程对齐《计算机网络实验一》8.7「事件驱动函数及程序流程」：
 *   for (;;) {
 *       event = wait_for_event(&arg);
 *       switch (event) { ... }
 *       if (...) enable_network_layer();
 *       else       disable_network_layer();
 *   }
 * 指导书示意图在循环前还有一次 enable_network_layer()；实现完整协议时可与
 * 流量控制策略统一考虑。骨架阶段先 disable 网络层，避免未调用 get_packet 时
 * 在 NETWORK_LAYER_READY 上忙等（8.6：须在该事件发生后才能 get_packet）。
 */

int main(int argc, char **argv)
{
    int event, arg;

    /* 8.5 协议运行环境的初始化 —— 必须是主程序第一步 */
    protocol_init(argc, argv);
    lprintf("Designed by Bosprimigenious & Team, build: " __DATE__ "  " __TIME__ "\n");

    disable_network_layer();

    for (;;) {
        event = wait_for_event(&arg);

        switch (event) {
        case NETWORK_LAYER_READY:
            /* 8.6：此时方可 get_packet；取走后网络层会再按需产生就绪事件 */
            break;

        case PHYSICAL_LAYER_READY:
            /* 8.8：发送队列低于约 50 字节；若当前无帧可发须记下“可发送”状态 */
            break;

        case FRAME_RECEIVED:
            /* 8.8 / 8.9：recv_frame 读帧，再用 crc32 验证 */
            break;

        case DATA_TIMEOUT:
            /* 8.7 / 8.10：arg 为超时定时器编号，用于重传对应发送窗口项 */
            break;

        case ACK_TIMEOUT:
            /* 8.7 / 8.10：搭载 ACK 定时器超时，单独发控制帧等 */
            break;
        }

        /* 8.6 / 8.7：根据发送缓冲区、滑动窗口与物理层是否就绪动态开关网络层 */
        if (0) {
            enable_network_layer();
        } else {
            disable_network_layer();
        }
    }

    return 0;
}
