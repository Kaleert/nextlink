package pro.kaleert.nextlink

import android.content.Context
import org.json.JSONObject
import java.util.Locale

/** Share the Flutter presentation catalog, also when no Flutter engine is alive. */
object NativeStrings {
    private val catalogs = mutableMapOf<String, JSONObject>()
    @Synchronized
    fun text(context: Context, source: String, vararg args: Any?): String {
        val settings = runCatching {
            JSONObject(context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .getString("flutter.app_settings", "{}") ?: "{}")
        }.getOrDefault(JSONObject())
        val language = when(settings.optString("language")) {
            "Русский" -> "ru"
            "Українська" -> "uk"
            "English" -> "en"
            else -> Locale.getDefault().language.let { if (it in setOf("ru", "uk", "en")) it else "en" }
        }
        val catalog = catalogs.getOrPut(language) {
            runCatching { context.assets.open("flutter_assets/assets/lang/ui_$language.json")
                .bufferedReader(Charsets.UTF_8).use { JSONObject(it.readText()) } }.getOrDefault(JSONObject())
        }
        return Regex("\\{(\\d+)\\}").replace(catalog.optString(source, source)) { match ->
            val index = match.groupValues[1].toIntOrNull()
            if (index != null && index in args.indices) args[index].toString() else match.value
        }
    }
}
