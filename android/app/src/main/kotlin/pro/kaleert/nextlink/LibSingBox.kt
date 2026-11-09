package pro.kaleert.nextlink

import android.util.Log

object LibSingBox {
    private var isLoaded = false

    fun load(path: String? = null) {
        if (isLoaded) return
        try {
            if (path != null) {
                System.load(path)
                Log.d("LibSingBox", "Successfully loaded libsingbox from $path")
            } else {
                System.loadLibrary("singbox")
                Log.d("LibSingBox", "Successfully loaded libsingbox from jniLibs")
            }
            isLoaded = true
        } catch (e: Throwable) {
            Log.e("LibSingBox", "Could not load libsingbox: ${e.message}")
        }
    }

    @JvmStatic
    external fun start(config: String): String
    
    @JvmStatic
    external fun stop()
    
    @JvmStatic
    external fun getVersion(): String
}
