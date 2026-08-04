-dontwarn com.stripe.android.pushProvisioning.PushProvisioningActivity$g
-dontwarn com.stripe.android.pushProvisioning.PushProvisioningActivityStarter$Args
-dontwarn com.stripe.android.pushProvisioning.PushProvisioningActivityStarter$Error
-dontwarn com.stripe.android.pushProvisioning.PushProvisioningActivityStarter
-dontwarn com.stripe.android.pushProvisioning.PushProvisioningEphemeralKeyProvider
-dontwarn kotlinx.parcelize.Parceler$DefaultImpls
-dontwarn kotlinx.parcelize.Parceler
-dontwarn kotlinx.parcelize.Parcelize
-keep class com.stripe.** { *; }

# ── Attributes R8 needs for reflection-based (de)serialization and to keep
#    readable stack traces in crash reports from a release build. ──────────
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses
-keepattributes SourceFile,LineNumberTable

# ── flutter_webrtc (org.webrtc) ─────────────────────────────────────────
# WebRTC's native (C++/JNI) layer calls back into these Java classes by
# name/signature. R8 can't see that reference from native code, so without
# an explicit keep it can strip or rename members the native side depends
# on — surfacing as a runtime UnsatisfiedLinkError or silent call failure
# only in a release build, never in debug (JNI errors are exactly the class
# of bug that a minified build must be smoke-tested for before shipping).
-keep class org.webrtc.** { *; }
-dontwarn org.webrtc.**

# ── socket_io_client → the underlying io.socket:socket.io-client /
#    engine.io-client Java libraries are plain jars (not AARs), so unlike
#    most Flutter plugins they don't ship their own consumer-rules.pro —
#    R8 needs these rules supplied here instead. ─────────────────────────
-keep class io.socket.** { *; }
-dontwarn io.socket.**
-keep class okhttp3.** { *; }
-dontwarn okhttp3.**
-keep class okio.** { *; }
-dontwarn okio.**
# Optional transitive dependencies socket.io/okhttp reference reflectively
# but this app never actually adds — without -dontwarn R8 fails the whole
# build with "Missing class" errors for these instead of just omitting them.
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**

# ── google_sign_in (Credential Manager / Play Services Auth) ───────────
-keep class com.google.android.gms.auth.** { *; }
-keep class com.google.android.gms.common.** { *; }
-keep class androidx.credentials.** { *; }
-dontwarn androidx.credentials.**
-keep class com.google.android.libraries.identity.googleid.** { *; }

# ── firebase_messaging / flutter_local_notifications ────────────────────
-keep class com.google.firebase.messaging.** { *; }
-keep class com.dexterous.** { *; }

# ── This app's own native call-in points (MainActivity's MethodChannel and
#    CallForegroundService are referenced by fully-qualified name from the
#    Flutter engine / AndroidManifest, not from any Kotlin call site R8 can
#    trace) ─────────────────────────────────────────────────────────────
-keep class com.humancareconnect.app.** { *; }
