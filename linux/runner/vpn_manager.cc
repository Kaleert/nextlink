#include "vpn_manager.h"
#include <iostream>
#include <string>
#include <vector>
#include <thread>
#include <mutex>
#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <signal.h>

static FlMethodChannel* vpn_channel = nullptr;
static FlMethodChannel* battery_channel = nullptr;
static FlMethodChannel* logger_channel = nullptr;

static pid_t active_core_pid = -1;
static pid_t test_core_pid = -1; // <-- ПЕРЕМЕННАЯ ДЛЯ ВТОРОГО ЯДРА

void send_native_log(const char* tag, const char* message) {
    if (logger_channel == nullptr) return;
    g_autoptr(FlValue) args = fl_value_new_map();
    fl_value_set_string_take(args, "tag", fl_value_new_string(tag));
    fl_value_set_string_take(args, "message", fl_value_new_string(message));
    fl_method_channel_invoke_method(logger_channel, "onNativeLog", args, nullptr, nullptr, nullptr);
}

static void stop_core() {
    if (active_core_pid > 0) {
        kill(active_core_pid, SIGTERM);
        waitpid(active_core_pid, nullptr, 0);
        active_core_pid = -1;
        send_native_log("CORE", "Core process terminated");
    }
}

static void stop_test_core() {
    if (test_core_pid > 0) {
        kill(test_core_pid, SIGTERM);
        waitpid(test_core_pid, nullptr, 0);
        test_core_pid = -1;
        send_native_log("CORE-TEST", "Test Core process terminated");
    }
}

static void handle_vpn_method_call(FlMethodChannel* channel, FlMethodCall* method_call, gpointer user_data) {
    const gchar* method = fl_method_call_get_name(method_call);
    FlValue* args = fl_method_call_get_args(method_call);
    g_autoptr(FlMethodResponse) response = nullptr;

    if (strcmp(method, "prepareVpn") == 0) {
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(true)));
    } else if (strcmp(method, "startVpn") == 0 || strcmp(method, "updateVpn") == 0 || strcmp(method, "startTestCore") == 0) {

        bool is_test = (strcmp(method, "startTestCore") == 0);
        const char* config = nullptr;
        const char* core_path = nullptr;

        if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
            FlValue* config_val = fl_value_lookup_string(args, "config");
            if (config_val && fl_value_get_type(config_val) == FL_VALUE_TYPE_STRING) config = fl_value_get_string(config_val);

            FlValue* coreType_val = fl_value_lookup_string(args, "coreType");
            const char* coreType = (coreType_val && fl_value_get_type(coreType_val) == FL_VALUE_TYPE_STRING) ? fl_value_get_string(coreType_val) : "XRAY";

            if (strcmp(coreType, "SINGBOX") == 0) {
                FlValue* sb_path_val = fl_value_lookup_string(args, "sbPath");
                if (sb_path_val && fl_value_get_type(sb_path_val) == FL_VALUE_TYPE_STRING) core_path = fl_value_get_string(sb_path_val);
            } else {
                FlValue* xray_path_val = fl_value_lookup_string(args, "xrayPath");
                if (xray_path_val && fl_value_get_type(xray_path_val) == FL_VALUE_TYPE_STRING) core_path = fl_value_get_string(xray_path_val);
            }
        }

        if (is_test) stop_test_core(); else stop_core();

        if (core_path == nullptr || strlen(core_path) == 0) {
            response = FL_METHOD_RESPONSE(fl_method_error_response_new("PATH_ERROR", "Core path missing", nullptr));
        } else {
            const char* cfg_name = is_test ? "config_test.json" : "config.json";
            if (config != nullptr) {
                FILE* f = fopen(cfg_name, "w");
                if (f) { fputs(config, f); fclose(f); }
            }

            pid_t pid = fork();
            if (pid == 0) {
                execl(core_path, core_path, "run", "-c", cfg_name, nullptr);
                exit(1);
            } else if (pid < 0) {
                response = FL_METHOD_RESPONSE(fl_method_error_response_new("FORK_ERROR", "Failed to start core", nullptr));
            } else {
                if (is_test) test_core_pid = pid; else active_core_pid = pid;
                send_native_log(is_test ? "CORE-TEST" : "CORE", "Process started on Linux");
                response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
            }
        }
    } else if (strcmp(method, "stopTestCore") == 0) {
        stop_test_core();
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    } else if (strcmp(method, "isRunning") == 0) {
        bool running = (active_core_pid > 0 && kill(active_core_pid, 0) == 0);
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(running)));
    } else if (strcmp(method, "isTestCoreRunning") == 0) {
        bool running = (test_core_pid > 0 && kill(test_core_pid, 0) == 0);
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(running)));
    } else if (strcmp(method, "stopVpn") == 0) {
        stop_core();
        stop_test_core();
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    } else {
        response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
    }

    fl_method_call_respond(method_call, response, nullptr);
}

static void handle_battery_method_call(FlMethodChannel* channel, FlMethodCall* method_call, gpointer user_data) {
    const gchar* method = fl_method_call_get_name(method_call);
    g_autoptr(FlMethodResponse) response = nullptr;

    if (strcmp(method, "isBatteryOptimizationDisabled") == 0) {
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(true)));
    } else {
        response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
    }
    fl_method_call_respond(method_call, response, nullptr);
}

void vpn_manager_init(FlView* view) {
    FlBinaryMessenger* messenger = fl_engine_get_binary_messenger(fl_view_get_engine(view));

    vpn_channel = fl_method_channel_new(messenger, "pro.kaleert.nextlink/vpn", FL_METHOD_CODEC(fl_standard_method_codec_new()));
    fl_method_channel_set_method_call_handler(vpn_channel, handle_vpn_method_call, nullptr, nullptr);

    battery_channel = fl_method_channel_new(messenger, "pro.kaleert.nextlink/battery", FL_METHOD_CODEC(fl_standard_method_codec_new()));
    fl_method_channel_set_method_call_handler(battery_channel, handle_battery_method_call, nullptr, nullptr);

    logger_channel = fl_method_channel_new(messenger, "pro.kaleert.nextlink/logger", FL_METHOD_CODEC(fl_standard_method_codec_new()));
}