CC = gcc
# -I./include 告诉编译器去哪里找头文件
CFLAGS = -Wall -g -I./include

SRCS = src/datalink.c src/protocol.c src/lprintf.c src/crc32.c
# Windows 下 protocol.c 使用 bundled getopt；Linux 使用系统 getopt_long，勿链接 getopt.c 以免与 libc 重复符号
ifeq ($(OS),Windows_NT)
SRCS += src/getopt.c
endif

OBJS = $(SRCS:.c=.o)
TARGET = datalink

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(CFLAGS) -o $@ $^ -lm

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f src/*.o $(TARGET) *.log

.PHONY: all clean
