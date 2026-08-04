allprojects {
    repositories {
        google()
        mavenCentral()
    }

    // stripe-android's Issuing "push provisioning" module (adding an issued
    // card to Google/Apple Wallet — a card-issuer feature this app doesn't
    // use or call into; PaymentSheet, the only Stripe UI this app uses,
    // doesn't touch it) itself depends on
    // com.google.android.gms:play-services-tapandpay:17.1.2, which is no
    // longer published at that coordinate in any configured repository.
    // Without this exclusion, :stripe_android's own lintVitalAnalyzeRelease
    // task fails to resolve its classpath and no release build (APK or AAB)
    // can complete at all, independent of anything else in this project.
    //
    // Only the missing leaf (play-services-tapandpay) is excluded, NOT
    // stripe-android-issuing-push-provisioning itself — flutter_stripe's own
    // Kotlin source (PushProvisioningProxy.kt, EphemeralKeyProvider.kt)
    // directly imports classes from that module, so excluding the module
    // wholesale breaks :stripe_android:compileReleaseKotlin outright (tried
    // that first). It never imports anything from play-services-tapandpay
    // directly, so excluding just that leaf still lets those classes
    // compile; the app also never calls flutter_stripe's push-provisioning
    // APIs from Dart, so nothing at runtime attempts to load the now-absent
    // tapandpay classes either. Must live here (root-level allprojects), not
    // in app/build.gradle.kts: :stripe_android is a sibling subproject, and
    // `app`'s own build script has no subprojects of its own for a
    // same-file `allprojects`/`configurations.all` to reach.
    configurations.all {
        exclude(group = "com.google.android.gms", module = "play-services-tapandpay")
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
