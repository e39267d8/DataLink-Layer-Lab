CC = gcc
CFLAGS = -Wall -g -I./include
LDLIBS =
BUILD_DIR = build
OBJ_DIR = $(BUILD_DIR)/obj
RM = rm -f

SRCS = src/datalink.c src/datalink_recv.c src/protocol.c src/lprintf.c src/crc32.c
# Windows 下 protocol.c 使用 bundled getopt；Linux 使用系统 getopt_long
ifeq ($(OS),Windows_NT)
SRCS += src/getopt.c
LDLIBS += -lws2_32
TARGET = $(BUILD_DIR)/datalink.exe
RM = del /Q
else
TARGET = $(BUILD_DIR)/datalink
endif

OBJS = $(SRCS:src/%.c=$(OBJ_DIR)/%.o)

all: $(TARGET)

$(TARGET): $(OBJS) | $(BUILD_DIR) $(OBJ_DIR)
	$(CC) $(CFLAGS) -o $@ $^ -lm $(LDLIBS)

$(OBJ_DIR)/%.o: src/%.c | $(OBJ_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR) $(OBJ_DIR):
	mkdir -p $@

clean:
	-$(RM) -r $(BUILD_DIR) 2>/dev/null
	-$(RM) datalink-A.log datalink-B.log 2>/dev/null

.PHONY: all clean
