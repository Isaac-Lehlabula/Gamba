package za.reclaim.reclaim_app.blocker

/**
 * Blocks a domain and every subdomain of it: "betway.co.za" also matches
 * "sport.betway.co.za", but not "notbetway.co.za".
 */
class DomainMatcher(domains: Collection<String>) {
    private val blocked: Set<String> = domains.map(::normalize).filter { it.isNotEmpty() }.toHashSet()

    val size: Int get() = blocked.size

    /** The listed domain that [name] falls under, or null if it isn't blocked. */
    fun match(name: String): String? {
        var candidate = normalize(name)
        while (true) {
            if (candidate in blocked) return candidate
            val dot = candidate.indexOf('.')
            if (dot < 0) return null
            candidate = candidate.substring(dot + 1)
        }
    }

    companion object {
        fun normalize(domain: String): String = domain.trim().lowercase().trimEnd('.').removePrefix("www.")
    }
}
