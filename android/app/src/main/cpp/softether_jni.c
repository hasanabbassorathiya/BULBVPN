#include <jni.h>
#include <stdint.h>
#include <stdbool.h>

typedef void *softether_client_t;

extern softether_client_t softether_create(
    const char *server, uint16_t port, const char *hub,
    const char *username, const char *password);
extern void softether_destroy(softether_client_t client);
extern int softether_connect(softether_client_t client);
extern int softether_disconnect(softether_client_t client);
extern void softether_request_stop(softether_client_t client);
extern void softether_set_verify_certificate(softether_client_t client, bool verify);
extern void softether_set_hostname(softether_client_t client, const char *hostname);
extern void softether_set_default_route(softether_client_t client, bool enabled);
extern void softether_set_reconnect(softether_client_t client, bool enabled, uint32_t max_attempts);
extern void softether_set_max_connections(softether_client_t client, uint8_t count);
extern void softether_set_udp_acceleration(softether_client_t client, bool enabled);
extern void softether_set_ip_version(softether_client_t client, int version);
extern void softether_set_connect_timeout(softether_client_t client, uint32_t ms);
extern void softether_set_read_timeout(softether_client_t client, uint32_t ms);
extern void softether_set_keepalive_interval(softether_client_t client, uint32_t ms);
extern void softether_set_tunnel_fd(softether_client_t client, int32_t fd);
extern int softether_replace_tun_fd(softether_client_t client, int32_t fd);
extern uint32_t softether_get_assigned_ip(const softether_client_t client);
extern uint32_t softether_get_assigned_mask(const softether_client_t client);
extern uint32_t softether_get_gateway_ip(const softether_client_t client);
extern bool softether_is_connected(const softether_client_t client);
extern uint32_t softether_get_effective_server_ip(const softether_client_t client);
extern void softether_set_android_protect(int (*cb)(int fd));
extern void softether_set_plain_password(softether_client_t client);
extern int softether_get_stats(const softether_client_t client, void *out);

typedef struct {
    uint64_t bytes_sent;
    uint64_t bytes_received;
    uint64_t packets_sent;
    uint64_t packets_received;
    int64_t connect_time_ms;
    uint32_t reconnect_count;
    uint32_t padding;
} softether_stats_t;

static JavaVM *g_vm = NULL;
static jobject g_service = NULL;

static int protect_cb(int fd) {
    if (g_vm == NULL || g_service == NULL) return -1;
    JNIEnv *env = NULL;
    int attached = 0;
    if ((*g_vm)->GetEnv(g_vm, (void **)&env, JNI_VERSION_1_6) == JNI_EDETACHED) {
        if ((*g_vm)->AttachCurrentThread(g_vm, &env, NULL) != 0) return -1;
        attached = 1;
    }
    jclass cls = (*env)->GetObjectClass(env, g_service);
    jmethodID mid = (*env)->GetMethodID(env, cls, "protectFd", "(I)I");
    int result = -1;
    if (mid != NULL) {
        result = (*env)->CallIntMethod(env, g_service, mid, fd);
    }
    if ((*env)->ExceptionCheck(env)) {
        (*env)->ExceptionClear(env);
        result = -1;
    }
    (*env)->DeleteLocalRef(env, cls);
    if (attached) (*g_vm)->DetachCurrentThread(g_vm);
    return result;
}

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM *vm, void *reserved) {
    (void)reserved;
    g_vm = vm;
    return JNI_VERSION_1_6;
}

JNIEXPORT void JNICALL
Java_app_bulbvpn_com_SoftEtherVpnService_nativeSetProtect(JNIEnv *env, jobject thiz) {
    if (g_service != NULL) {
        (*env)->DeleteGlobalRef(env, g_service);
    }
    g_service = (*env)->NewGlobalRef(env, thiz);
    softether_set_android_protect(protect_cb);
}

JNIEXPORT jlong JNICALL
Java_app_bulbvpn_com_SoftEtherVpnService_nativeCreate(
    JNIEnv *env, jobject thiz,
    jstring host, jint port, jstring hub, jstring user, jstring pass) {
    (void)thiz;
    const char *h = (*env)->GetStringUTFChars(env, host, NULL);
    const char *hu = (*env)->GetStringUTFChars(env, hub, NULL);
    const char *u = (*env)->GetStringUTFChars(env, user, NULL);
    const char *p = (*env)->GetStringUTFChars(env, pass, NULL);
    softether_client_t client = softether_create(h, (uint16_t)port, hu, u, p);
    (*env)->ReleaseStringUTFChars(env, host, h);
    (*env)->ReleaseStringUTFChars(env, hub, hu);
    (*env)->ReleaseStringUTFChars(env, user, u);
    (*env)->ReleaseStringUTFChars(env, pass, p);
    return (jlong)client;
}

JNIEXPORT void JNICALL
Java_app_bulbvpn_com_SoftEtherVpnService_nativeConfigure(
    JNIEnv *env, jobject thiz, jlong client, jstring sni, jboolean plain) {
    (void)thiz;
    softether_client_t c = (softether_client_t)client;
    const char *s = (*env)->GetStringUTFChars(env, sni, NULL);
    softether_set_verify_certificate(c, false);
    softether_set_hostname(c, s);
    softether_set_default_route(c, false);
    softether_set_reconnect(c, true, 3);
    softether_set_max_connections(c, 1);
    softether_set_udp_acceleration(c, false);
    softether_set_ip_version(c, 4);
    softether_set_connect_timeout(c, 12000);
    // Keep the CGNAT mapping in Irancell/other carriers alive and fail a
    // black-holed session instead of reporting it as connected forever.
    softether_set_keepalive_interval(c, 15000);
    softether_set_read_timeout(c, 30000);
    if (plain) softether_set_plain_password(c);
    (*env)->ReleaseStringUTFChars(env, sni, s);
}

JNIEXPORT void JNICALL
Java_app_bulbvpn_com_SoftEtherVpnService_nativeSetTun(
    JNIEnv *env, jobject thiz, jlong client, jint fd) {
    (void)env;
    (void)thiz;
    softether_set_tunnel_fd((softether_client_t)client, fd);
}

JNIEXPORT jint JNICALL
Java_app_bulbvpn_com_SoftEtherVpnService_nativeConnect(
    JNIEnv *env, jobject thiz, jlong client) {
    (void)env;
    (void)thiz;
    return softether_connect((softether_client_t)client);
}

JNIEXPORT void JNICALL
Java_app_bulbvpn_com_SoftEtherVpnService_nativeRequestStop(
    JNIEnv *env, jobject thiz, jlong client) {
    (void)env;
    (void)thiz;
    softether_request_stop((softether_client_t)client);
}

JNIEXPORT jint JNICALL
Java_app_bulbvpn_com_SoftEtherVpnService_nativeAssignedIp(
    JNIEnv *env, jobject thiz, jlong client) {
    (void)env;
    (void)thiz;
    return (jint)softether_get_assigned_ip((softether_client_t)client);
}

JNIEXPORT jint JNICALL
Java_app_bulbvpn_com_SoftEtherVpnService_nativeAssignedMask(
    JNIEnv *env, jobject thiz, jlong client) {
    (void)env;
    (void)thiz;
    return (jint)softether_get_assigned_mask((softether_client_t)client);
}

JNIEXPORT jint JNICALL
Java_app_bulbvpn_com_SoftEtherVpnService_nativeGatewayIp(
    JNIEnv *env, jobject thiz, jlong client) {
    (void)env;
    (void)thiz;
    return (jint)softether_get_gateway_ip((softether_client_t)client);
}

JNIEXPORT jboolean JNICALL
Java_app_bulbvpn_com_SoftEtherVpnService_nativeIsConnected(
    JNIEnv *env, jobject thiz, jlong client) {
    (void)env;
    (void)thiz;
    return softether_is_connected((softether_client_t)client) ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jint JNICALL
Java_app_bulbvpn_com_SoftEtherVpnService_nativeEffectiveServerIp(
    JNIEnv *env, jobject thiz, jlong client) {
    (void)env;
    (void)thiz;
    return (jint)softether_get_effective_server_ip((softether_client_t)client);
}

JNIEXPORT jint JNICALL
Java_app_bulbvpn_com_SoftEtherVpnService_nativeReplaceTun(
    JNIEnv *env, jobject thiz, jlong client, jint fd) {
    (void)env;
    (void)thiz;
    return softether_replace_tun_fd((softether_client_t)client, fd);
}

JNIEXPORT void JNICALL
Java_app_bulbvpn_com_SoftEtherVpnService_nativeStop(
    JNIEnv *env, jobject thiz, jlong client) {
    (void)env;
    (void)thiz;
    softether_request_stop((softether_client_t)client);
    softether_disconnect((softether_client_t)client);
}

JNIEXPORT jlong JNICALL
Java_app_bulbvpn_com_SoftEtherVpnService_nativeBytesDown(
    JNIEnv *env, jobject thiz, jlong client) {
    (void)env;
    (void)thiz;
    softether_stats_t stats;
    if (softether_get_stats((softether_client_t)client, &stats) != 0) return 0;
    return (jlong)stats.bytes_received;
}

JNIEXPORT void JNICALL
Java_app_bulbvpn_com_SoftEtherVpnService_nativeDestroy(
    JNIEnv *env, jobject thiz, jlong client) {
    (void)env;
    (void)thiz;
    softether_destroy((softether_client_t)client);
}
