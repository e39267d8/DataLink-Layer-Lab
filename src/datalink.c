/*
 * 这个文件做5件事：维护发送窗口、发送新 DATA 帧、
 * 收到 ACK 后滑动窗口、超时后 GBN 回退重传、根据物理层状态开关网络层
 * 数据链路层主控 —— 张恒基：事件循环 + GBN 发送侧状态机。
 * 接收校验、纯 ACK 组帧见 datalink_recv.c（尹浩铭接口）。
 */

#include <stdio.h>
#include <string.h>
#include "protocol.h" //引入老师提供的 `protocol.h`
#include "datalink.h" //引入自己的 `datalink.h`

/* ---------- 发送窗口全局状态 ---------- */
static unsigned char ack_expected; //发送窗口下界，表示“最老的还没被确认的帧序号”
static unsigned char next_frame_to_send; //下一个要发送的新数据帧序号
static unsigned char frame_buffer[NR_BUFS][MAX_FRAME_BYTES]; 
//保存已经发出但可能还要重传的帧内容。GBN 超时时要从窗口下界开始重发，所以必须缓存
static int frame_saved_len[NR_BUFS];
//每个缓存帧的真实长度。DATA 帧通常是 263 字节

/* 物理层发送队列低于阈值后为 1；send_frame 后置 0，等待 PHYSICAL_LAYER_READY */
//物理层是否允许继续塞帧。`1` 表示可以，`0` 表示刚发过帧，需要等物理层 ready
static int phl_ready = 1;

/* 计算当前窗口里有多少未确认帧，定义静态函数 `nbuffered`，只在本文件内部用 */
static unsigned nbuffered(void)
{
    unsigned M = (unsigned)(MAX_SEQ + 1); //当前是 `256`，因为序号是 `0..255`
    return (unsigned)((next_frame_to_send + M - ack_expected) % M);
    /* 计算 `(next_frame_to_send - ack_expected) mod M`。  
例如 `ack_expected=3`，`next_frame_to_send=7`，说明 3、4、5、6 还没确认，结果是 4。  
如果序号回绕，比如 `ack_expected=254`，`next_frame_to_send=2`，结果是 4，对应 254、255、0、1
*/
}

/* 序号加一并回绕，输入一个序号，返回下一个序号 */
static unsigned char inc_seq(unsigned char s)
{
    return (unsigned char)((s + 1) % (MAX_SEQ + 1));
    // 所以 `255` 的下一个是 `0`。这是滑动窗口协议处理循环序号的基础
}

/* 收到 ACK 后滑动发送窗口 */
void update_ack_received(unsigned char ack_seq)
{
    unsigned M = (unsigned)(MAX_SEQ + 1); //取序号空间大小 `M=256`
    unsigned w = (unsigned)((next_frame_to_send + M - ack_expected) % M);
    //`w` 是当前窗口里未确认帧数
    unsigned d = (unsigned)((ack_seq + M - ack_expected) % M);
    //`d` 是 ACK 到窗口下界的距离，也就是这个 ACK 想确认多少进度

    if (d == 0U || d > w)
        return;
    /* 如果 `d==0`，说明 ACK 没有推进窗口，忽略；
     * 如果 `d>w`，说明 ACK 超出了当前发送窗口，也忽略
     */

    ack_expected = ack_seq; //ACK 合法，直接把窗口下界推进到 `ack_seq`
    stop_timer(DATA_TIMER_ID);
    //先停止旧的数据定时器。因为窗口已经变了，旧定时器对应的最老未确认帧可能已经不是原来的了
    if (ack_expected != next_frame_to_send) {
        //如果推进后仍有未确认帧，说明窗口还没空
        /* start_timer: 实际超时发生在物理层队列排空折算时间之后 + timeout_ms，
         * 与指导书 8.10 及本仓库 protocol.c 中 start_timer 实现一致。 
         * 老师库的 `start_timer` 会考虑物理层队列排队时间*/
        start_timer(DATA_TIMER_ID, DATA_TIMEOUT_MS);
        // 重新启动数据定时器，保护新的最老未确认帧
    }
}

/* 发送一个新的 DATA 帧,网络层有数据可发时调用 */
static void send_one_data_frame(void)
{
    unsigned char tx[MAX_FRAME_BYTES]; //`tx` 是临时发送缓冲区，最多放一整个帧
    unsigned int crc; //`crc` 保存 CRC-32 结果
    int idx; //`idx` 是缓存数组下标
    int wire_len = FRAME_HDR_LEN + PKT_LEN + (int)sizeof(unsigned int);
    //计算线路上的 DATA 帧长度：帧头 3 字节 + 载荷 256 字节 + CRC 4 字节

    /* 如果窗口满了，就不能再从网络层取包，直接返回 */
    if (nbuffered() >= (unsigned)WINDOW_SIZE)
        return;

    tx[0] = FRAME_DATA; //帧类型设为 `FRAME_DATA`
    tx[1] = next_frame_to_send; //帧序号设为 `next_frame_to_send`
    tx[2] = dl_get_frame_expected(); // 把本端接收侧“下一帧期望序号”放进 ACK 字段，这就是捎带 ACK
    // 从网络层取 256 字节分组，填到帧头后面。如果没取到完整分组，就返回
    if (get_packet(tx + FRAME_HDR_LEN) != PKT_LEN)
        return;

    crc = crc32(tx, (unsigned int)(FRAME_HDR_LEN + PKT_LEN)); //对“帧头 + 数据载荷”计算 CRC
    memcpy(tx + FRAME_HDR_LEN + PKT_LEN, &crc, sizeof(crc)); //把 CRC 追加到帧尾

    idx = next_frame_to_send % NR_BUFS;
    //用序号对 `NR_BUFS` 取模，得到缓存位置。当前 `NR_BUFS=256`，其实就是序号本身
    memcpy(frame_buffer[idx], tx, (size_t)wire_len); //把完整帧复制到缓存，供之后重传使用
    frame_saved_len[idx] = wire_len; //保存这个帧的长度

    send_frame(tx, wire_len); //调用老师库 `send_frame`，把帧交给物理层发送
    phl_ready = 0; //刚向物理层塞了一帧，所以认为物理层暂时不 ready
    next_frame_to_send = inc_seq(next_frame_to_send); //发送序号加一，准备下一个新帧

    stop_timer(DATA_TIMER_ID); //停止旧数据定时器
    /* 如果当前还有未确认帧，就启动数据定时器。这里保护的是窗口下界那一批未确认帧 */
    if (ack_expected != next_frame_to_send)
        start_timer(DATA_TIMER_ID, DATA_TIMEOUT_MS);
}

/* GBN 超时回退重传，数据超时时调用 */
static void resend_window(void)
{
    unsigned char s = ack_expected; // 从 `ack_expected` 开始重传，也就是窗口下界
    //一直重传到 `next_frame_to_send` 之前
    while (s != next_frame_to_send) {
        int idx = s % NR_BUFS; //根据序号找到缓存下标
        send_frame(frame_buffer[idx], frame_saved_len[idx]);
        //把缓存里的旧帧重新发出去。注意不是重新 `get_packet`，而是发原来的帧
        s = inc_seq(s); //序号加一，继续重传下一个未确认帧
    }
    phl_ready = 0; //重传也向物理层塞了帧，所以 `phl_ready=0`
    stop_timer(DATA_TIMER_ID); //停止旧定时器
    
    /* 如果重传后仍有未确认帧，重新启动数据定时器。否则如果这时窗口空了，就不用定时器
     * Go-Back-N 的核心：不是只重传坏掉那一帧，而是从最早未确认帧开始全部重传*/
    if (ack_expected != next_frame_to_send)
        start_timer(DATA_TIMER_ID, DATA_TIMEOUT_MS);
}

/* 网络层闸门，每轮事件处理后调用 */
static void refresh_network_layer_gate(void)
{
    /* 与 protocol.c 中 PHL_SQ_LEVEL(50) 一致；队列已排空则视为可发，避免漏掉 READY 事件 */
    /* 如果老师库报告物理层队列长度小于 50，就认为物理层可以继续写，
     * 设置 `phl_ready=1`。这是后期性能提升的关键 */
    if (phl_sq_len() < 50)
        phl_ready = 1;

    //只有两个条件同时满足，才打开网络层：窗口没满，且物理层 ready
    if (nbuffered() < (unsigned)WINDOW_SIZE && phl_ready)
        enable_network_layer(); //允许网络层产生 `NETWORK_LAYER_READY` 事件
    else
        disable_network_layer();//否则关闭网络层，避免继续取包导致窗口溢出或物理层队列堆积
}

/* 主函数入口，命令行参数传给老师库 */
int main(int argc, char **argv)
{
    int event, arg; //`event` 存事件类型，`arg` 存事件附带参数
    unsigned char rxbuf[512]; //接收缓冲区，用来放收到的原始帧。512 足够容纳最大 263 字节 DATA 帧

    protocol_init(argc, argv); //初始化老师库，包括网络层、物理层、事件系统、命令行参数
    lprintf("datalink GBN build: " __DATE__ " " __TIME__ "\n"); //打印编译时间，方便确认跑的是最新版本

    ack_expected = 0; //发送窗口下界从 0 开始
    next_frame_to_send = 0; //下一个发送序号也从 0 开始
    /* 一开始先关闭网络层，后面由 `refresh_network_layer_gate` 根据窗口和物理层状态打开 */
    disable_network_layer();

    /* 事件循环，无限循环，协议一直运行 */
    for (;;) {
        event = wait_for_event(&arg); //等待老师库给一个事件，比如网络层可发、收到帧、超时等
        //根据事件类型分支处理
        switch (event) {
        case NETWORK_LAYER_READY:
            send_one_data_frame();
            break;
            //网络层有新分组可取，就调用 `send_one_data_frame()` 发送一个 DATA 帧

        case PHYSICAL_LAYER_READY:
            phl_ready = 1;
            break;
            //物理层队列低于阈值，可以继续写帧，所以 `phl_ready=1`

        /* 收到一帧 */
        case FRAME_RECEIVED: {
            int len, rc; //`len` 存帧长度，`rc` 存接收模块处理结果
            unsigned int ack_seq = 0; //`ack_seq` 存收到帧里携带的 ACK
            unsigned char data_out[PKT_LEN]; //`data_out` 用来接收正确 DATA 帧的载荷
            int data_len = 0; //`data_len` 存载荷长度

            len = recv_frame(rxbuf, (int)sizeof(rxbuf)); //从物理层取出收到的帧
            rc = validate_and_process_frame(rxbuf, len, &ack_seq, data_out, &data_len);
            /* 交给 `validate_and_process_frame` 做长度检查、CRC 检查、ACK 提取、按序判断
             * 如果返回负数，说明坏帧或非法帧，丢弃并跳出本事件 */
            if (rc < 0) {
                dbg_warning("CRC error or bad frame, dropped\n");
                break;//无论是纯 ACK 还是 DATA 帧，只要合法，都先用其中 ACK 更新发送窗口
            }
            //无论是纯 ACK 还是 DATA 帧，只要合法，都先用其中 ACK 更新发送窗口
            update_ack_received((unsigned char)ack_seq);
            if (rc == 1)//如果 `rc==1`，说明收到的是按序正确 DATA，于是交付网络层
                put_packet(data_out, data_len);
            /* 如果收到 DATA，不管是否按序，都启动 ACK 定时器，之后如果没有反向数据可捎带 ACK，就发纯 ACK */
            if (rc == 1 || rc == 2)
                start_ack_timer(ACK_TIMEOUT_MS);
            break;
        }

        /* 数据超时 */
        case DATA_TIMEOUT:
            (void)arg; //显式表示 `arg` 不使用，避免编译警告
            resend_window(); //调用 `resend_window()`，从窗口下界开始 GBN 回退重传
            break;

        /* ACK定时器超时 */
        case ACK_TIMEOUT:
            send_pure_ack(dl_get_frame_expected()); //发送纯 ACK，ACK 值是本端接收侧当前期望的下一个 DATA 序号
            phl_ready = 0; //发送纯 ACK 也调用了 `send_frame`，所以物理层暂时置为不 ready
            stop_ack_timer(); //停止 ACK 定时器
            break;

        default:
            break;//其他事件不处理，直接跳过
        }

        /* 每处理完一个事件，就刷新网络层闸门，决定是否允许继续取新包 */
        refresh_network_layer_gate();
    }

    /* not reached */
}
