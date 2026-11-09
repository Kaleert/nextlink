package pro.kaleert.nextlink

fun main() {
    check(AutomationPolicy.networkTrigger(setOf("wifi", "timeout"), "wifi", "mobile", false, false) == "wifi")
    check(AutomationPolicy.networkTrigger(setOf("wifi_to_mobile"), "mobile", "wifi", false, false) == "wifi_to_mobile")
    check(AutomationPolicy.networkTrigger(setOf("network_change"), "none", "wifi", false, false).isEmpty())
    check(AutomationPolicy.networkTrigger(setOf("hotspot"), "mobile", "mobile", true, false) == "hotspot")
    check(AutomationPolicy.networkTrigger(setOf("wifi"), "wifi", "wifi", false, false).isEmpty())
    check(AutomationPolicy.target(listOf("a", "b", "c"), setOf("b", "c"), null, "b", false) == "c")
    check(AutomationPolicy.target(listOf("a", "b", "c"), setOf("b", "c"), "b", "b", true) == "c")
    check(AutomationPolicy.target(listOf("a", "b", "c"), setOf("b", "c"), "b", "c", false) == "b")
    check(AutomationPolicy.target(listOf("a"), setOf("deleted"), null, "a", false) == null)
    check(AutomationPolicy.target(listOf("a", "b"), emptySet(), null, null, false) == "a")
    println("10 native automation policy checks passed")
}
