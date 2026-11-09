package pro.kaleert.nextlink

import org.json.JSONArray
import org.json.JSONObject

/** Android routing and TUN decisions must agree, including shared UIDs. */
data class AppUidPolicy(
    val actions: Map<Int, String>, val allowedPackages: Set<String>,
    val directPackages: Set<String>, val whitelist: Boolean,
    val defaultBlock: Boolean, val blocking: Boolean, val capturesTraffic: Boolean
) {
    fun bridgeJson(): String = JSONObject().apply {
        put("blocked", JSONArray(actions.filterValues { it == "block" }.keys.toList()))
        put("allowed", JSONArray(actions.filterValues { it == "proxy" }.keys.toList()))
        put("defaultBlock", defaultBlock)
        put("blockUnknown", blocking)
    }.toString()
    companion object {
        fun build(packages: Map<String, Int>, ownUid: Int, enabled: Boolean, defaultRule: String, rules: Map<String, String>): AppUidPolicy {
            val valid = setOf("proxy", "direct", "block")
            val fallback = if (defaultRule in valid) defaultRule else "proxy"
            val actions = packages.entries.groupBy { it.value }.mapValues { (uid, entries) ->
                if (uid == ownUid) "direct" else if (!enabled) "proxy" else {
                    val choices = entries.map { rules[it.key]?.takeIf(valid::contains) ?: fallback }
                    when { "block" in choices -> "block"; "proxy" in choices -> "proxy"; else -> "direct" }
                }
            }
            val allowed = packages.filter { it.value != ownUid && actions[it.value] != "direct" }.keys
            val direct = packages.filter { actions[it.value] == "direct" }.keys
            val whitelist = enabled && fallback == "direct"
            val defaultBlock = enabled && fallback == "block"
            return AppUidPolicy(actions, allowed, direct, whitelist, defaultBlock,
                enabled && (defaultBlock || actions.values.any { it == "block" }), !whitelist || allowed.isNotEmpty())
        }
    }
}
