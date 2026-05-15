CC = gcc
# -I./include 告诉编译器去哪里找头文件
CFLAGS = -Wall -g -I./include
LDLIBS =
RM = rm -f

SRCS = src/datalink.c src/datalink_recv.c src/protocol.c src/lprintf.c src/crc32.c
# Windows 下 protocol.c 使用 bundled getopt；Linux 使用系统 getopt_long，勿链接 getopt.c 以免与 libc 重复符号
ifeq ($(OS),Windows_NT)
SRCS += src/getopt.c
LDLIBS += -lws2_32
TARGET = datalink.exe
RM = del /Q
OBJ_GLOB = src\*.o
LOG_GLOB = *.log
else
TARGET = datalink
OBJ_GLOB = src/*.o
LOG_GLOB = *.log
endif

OBJS = $(SRCS:.c=.o)

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(CFLAGS) -o $@ $^ -lm $(LDLIBS)

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	-$(RM) $(OBJ_GLOB) $(TARGET) $(LOG_GLOB)

.PHONY: all clean
