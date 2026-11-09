package pro.kaleert.nextlink

/** Pure decision logic, independent of Android lifecycle or Flutter. */
object AutomationPolicy {
    fun networkTrigger(triggers: Set<String>, network: String, previous: String?, hotspot: Boolean, previousHotspot: Boolean): String = when {
        "any_network" in triggers && network != "none" && (previous == null || previous == "none") -> "any_network"
        "wifi" in triggers && network == "wifi" && previous != "wifi" -> "wifi"
        "mobile" in triggers && network == "mobile" && previous != "mobile" -> "mobile"
        "wifi_to_mobile" in triggers && previous == "wifi" && network == "mobile" -> "wifi_to_mobile"
        "network_change" in triggers && previous != null && previous != network && network != "none" -> "network_change"
        "hotspot" in triggers && hotspot && !previousHotspot -> "hotspot"
        else -> ""
    }
    fun target(all: List<String>, group: Set<String>, pinned: String?, current: String?, timeout: Boolean): String? {
        val targets = all.filter { group.isEmpty() || it in group || it == pinned }
        if (targets.isEmpty()) return null
        if (pinned in targets && (!timeout || pinned != current)) return pinned
        return targets[(targets.indexOf(current) + 1).mod(targets.size)]
    }
}
