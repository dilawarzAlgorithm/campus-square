# 1. Keep Attributes (CRUCIAL for Gson and JSON serialization)
-keepattributes Signature, Annotation, EnclosingMethod, InnerClasses, Exceptions

# 2. Keep local notifications native code & Background Models
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keepclassmembers class com.dexterous.flutterlocalnotifications.** { *; }
-keep class com.dexterous.flutterlocalnotifications.models.** { *; }

# 3. Keep Gson (Required for reading offline alarms in background)
-keep class com.google.gson.** { *; }
-keepclassmembers class com.google.gson.** { *; }
-keep class sun.misc.Unsafe { *; }
-keep class com.google.gson.stream.** { *; }

# 4. Keep Java 8 Time APIs (Desugaring) needed for timezone scheduling
-keep class j$.time.** { *; }
-keepclassmembers class j$.time.** { *; }

# 5. Keep Storage & Encryption (Prevents app from losing saved login tokens)
-keep class androidx.security.crypto.** { *; }
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-keep class io.flutter.plugins.sharedpreferences.** { *; }

# 6. Keep Firebase & Google Mobile Services (Prevents Firebase Auth from failing)
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }