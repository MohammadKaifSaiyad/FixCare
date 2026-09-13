# Razorpay (razorpay_flutter) — keep SDK + its Google Pay / annotation deps.
-keepclassmembers class * { @android.webkit.JavascriptInterface <methods>; }
-keepattributes JavascriptInterface
-keep class com.razorpay.** { *; }
-keep class proguard.annotation.** { *; }
-dontwarn com.razorpay.**
-dontwarn proguard.annotation.**
