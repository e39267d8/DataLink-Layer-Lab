#!/usr/bin/env python3
"""
全场景自动化压测脚本 —— 填满《性能测试记录表》表 3
每个场景运行 > 20 分钟（1210 秒），5 个场景总耗时约 100 分钟。

修复：使用 -l 标志为每个场景指定唯一日志文件名，写入 build/ 目录。
"""

import subprocess
import time
import re
import os
import sys
from datetime import datetime

# ---------- 配置 ----------
EXE = os.path.join("build", "datalink.exe")
BUILD_DIR = "build"
RUN_SECS = 1210      # 每个场景运行秒数（严格 > 20 min）
STARTUP_DELAY = 1.0  # B 与 A 启动间隔（秒）

SCENARIOS = [
    {"id": 1, "desc": "无误码 (Utopia)",           "args_a": "-u",       "args_b": "-u"},
    {"id": 2, "desc": "默认误码",                   "args_a": "",          "args_b": ""},
    {"id": 3, "desc": "无误码洪水 (Flood+Utopia)",  "args_a": "-f -u",    "args_b": "-f -u"},
    {"id": 4, "desc": "默认误码洪水 (Flood)",       "args_a": "-f",       "args_b": "-f"},
    {"id": 5, "desc": "高误码洪水 (Flood+BER=1e-4)","args_a": "-f -b 1e-4","args_b": "-f -b 1e-4"},
]


def log(msg: str):
    ts = datetime.now().strftime("%H:%M:%S")
    print(f"[{ts}] {msg}", flush=True)


def log_path(sid: int, station: str) -> str:
    """场景 sid 的 station (A/B) 日志绝对路径"""
    return os.path.join(BUILD_DIR, f"scene{sid}-{station}.log")


def clean_all_logs():
    """清理 build/ 下所有残留日志"""
    for f in os.listdir(BUILD_DIR):
        if f.endswith(".log"):
            p = os.path.join(BUILD_DIR, f)
            try:
                os.remove(p)
            except Exception:
                pass
    # 同时清理根目录残留
    for f in ("datalink-A.log", "datalink-B.log"):
        if os.path.exists(f):
            os.remove(f)


def start_station(args: str, station: str, scene_id: int) -> subprocess.Popen:
    """启动一个 datalink 进程，日志写入 build/scene{id}-{station}.log"""
    log_path_str = log_path(scene_id, station)
    cmd_parts = [EXE] + args.split() + ["-l", log_path_str, station] if args.strip() else [EXE, "-l", log_path_str, station]
    # 过滤空字符串
    cmd_parts = [c for c in cmd_parts if c]
    log(f"  启动 Station {station}: {' '.join(cmd_parts)}")
    return subprocess.Popen(
        cmd_parts,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        cwd=None,  # inherit parent cwd (project root)
    )


def kill_proc(proc: subprocess.Popen, name: str):
    if proc is None:
        return
    try:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
        log(f"  已终止 {name} (PID {proc.pid})")
    except Exception as e:
        log(f"  终止 {name} 时出错: {e}")


def extract_last_util(path: str) -> float | None:
    """从日志中提取最后一条 bps/% 行的利用率浮点数"""
    if not os.path.exists(path):
        log(f"  WARNING: log not found: {path}")
        return None
    pattern = re.compile(r"(\d+\.?\d*)\s*%")
    last_pct = None
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            if "bps" in line and "%" in line:
                m = pattern.search(line)
                if m:
                    last_pct = float(m.group(1))
    return last_pct


def count_frames_and_errors(path: str) -> tuple[int, int]:
    """提取最后一条记录的累计接收分组数和错误计数"""
    pkts, errs = 0, 0
    if not os.path.exists(path):
        return 0, 0
    pkt_pat = re.compile(r"(\d+)\s+packets\s+received")
    err_pat = re.compile(r"Err\s+(\d+)")
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            if "bps" not in line or "%" not in line:
                continue
            pm = pkt_pat.search(line)
            em = err_pat.search(line)
            if pm:
                pkts = int(pm.group(1))
            if em:
                errs = int(em.group(1))
    return pkts, errs


def run_scenario(scenario: dict) -> dict:
    """执行单个场景"""
    sid = scenario["id"]
    desc = scenario["desc"]
    log(f"\n{'='*60}")
    log(f"场景 {sid}/5: {desc}")
    log(f"{'='*60}")

    # 1. 启动 B 站（客户端，先启动）
    proc_b = start_station(scenario["args_b"], "B", sid)
    time.sleep(STARTUP_DELAY)

    # 2. 启动 A 站（服务端，后启动）
    proc_a = start_station(scenario["args_a"], "A", sid)

    # 3. 挂机
    t0 = time.time()
    log(f"  挂机 {RUN_SECS}s ({RUN_SECS // 60} min) ...")
    remaining = RUN_SECS
    while remaining > 0:
        chunk = min(60, remaining)
        time.sleep(chunk)
        remaining -= chunk
        elapsed = int(time.time() - t0)
        if elapsed % 300 < 60:
            log(f"  ... {elapsed}s / {RUN_SECS}s ({elapsed * 100 // RUN_SECS}%)")

    elapsed = int(time.time() - t0)
    log(f"  运行完成，实际 {elapsed}s")

    # 4. 终止进程
    kill_proc(proc_a, "A")
    kill_proc(proc_b, "B")
    time.sleep(1.0)  # 等待文件刷新

    # 5. 解析日志
    path_a = log_path(sid, "A")
    path_b = log_path(sid, "B")
    util_a = extract_last_util(path_a)
    util_b = extract_last_util(path_b)
    pkts_a, errs_a = count_frames_and_errors(path_a)
    pkts_b, errs_b = count_frames_and_errors(path_b)

    log(f"  RESULT A: {util_a}% ({pkts_a} pkts, {errs_a} err)  |  B: {util_b}% ({pkts_b} pkts, {errs_b} err)")

    return {
        "id": sid, "desc": desc, "time": elapsed,
        "A": util_a, "B": util_b,
        "pkts_a": pkts_a, "pkts_b": pkts_b,
        "errs_a": errs_a, "errs_b": errs_b,
    }


def print_table(results: list[dict]):
    print()
    print("=" * 90)
    print("              性 能 测 试 记 录 表（表 3）")
    print("=" * 90)
    print()
    hdr = "| 序号 | 场景说明 | 运行时长 | GoBackN A站利用率 | GoBackN B站利用率 | Selective A站 | Selective B站 | 备注 |"
    sep = "|------|----------|----------|-------------------|-------------------|---------------|---------------|------|"
    print(hdr)
    print(sep)
    for r in results:
        a_s = f"{r['A']:.2f}%" if r['A'] is not None else "—"
        b_s = f"{r['B']:.2f}%" if r['B'] is not None else "—"
        ea, eb = r.get('errs_a', 0), r.get('errs_b', 0)
        if r['id'] <= 2:
            remark = "无坏分组" if (ea == 0 and eb == 0) else f"Err A:{ea}/B:{eb}"
        else:
            remark = f"Flood" + ("; 无坏分组" if (ea == 0 and eb == 0) else f"; Err A:{ea}/B:{eb}")
        print(f"| {r['id']} | {r['desc']} | {r['time']}s | {a_s} | {b_s} | — | — | {remark} |")
    print()
    print("> 协议：搭载 ACK 的 Go-Back-N（GBN）")
    print("> 参数：WINDOW_SIZE=5, DATA_TIMEOUT=600ms, ACK_TIMEOUT=50ms, MAX_SEQ=255")
    print(f"> 可执行文件：{os.path.abspath(EXE)}")
    print(f"> 测试日期：{datetime.now().strftime('%Y-%m-%d')}")
    print()


def main():
    log("=" * 60)
    log("全场景压测启动 —— 5 场景 × 20+ 分钟 ≈ 100 分钟")
    log(f"可执行文件: {os.path.abspath(EXE)}")
    log("=" * 60)

    if not os.path.exists(EXE):
        log(f"ERROR: cannot find {EXE}, please build first!")
        sys.exit(1)

    # 清理所有残留日志
    clean_all_logs()
    log("残留日志已清理\n")

    results = []
    total = len(SCENARIOS)
    t_start = time.time()

    for i, scenario in enumerate(SCENARIOS):
        try:
            result = run_scenario(scenario)
            results.append(result)
        except Exception as e:
            log(f"ERROR: scene {i+1} exception: {e}")
            import traceback
            traceback.print_exc()
            results.append({
                "id": scenario["id"], "desc": scenario["desc"],
                "time": 0, "A": None, "B": None,
                "pkts_a": 0, "pkts_b": 0, "errs_a": 0, "errs_b": 0,
            })

        elapsed_m = (time.time() - t_start) / 60
        remaining_m = elapsed_m / (i + 1) * (total - i - 1) if i < total - 1 else 0
        log(f"[{elapsed_m:.0f} min elapsed | ~{remaining_m:.0f} min remaining]")

    print_table(results)
    log("All 5 scenarios completed!")


if __name__ == "__main__":
    main()
