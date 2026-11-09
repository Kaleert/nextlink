package pro.kaleert.nextlink

import android.util.Log

object LibXray {
    private var isLoaded = false

    fun load(path: String? = null) {
        if (isLoaded) return
        try {
            if (path != null) {
                System.load(path)
                Log.d("LibXray", "Successfully loaded libxray from $path")
            } else {
                System.loadLibrary("xray")
                Log.d("LibXray", "Successfully loaded libxray from jniLibs")
            }
            isLoaded = true
        } catch (e: Throwable) {
            Log.e("LibXray", "Could not load libxray: ${e.message}")
        }
    }

    @JvmStatic
    external fun start(config: String): String
    
    @JvmStatic
    external fun stop()
    
    @JvmStatic
    external fun getVersion(): String
}
