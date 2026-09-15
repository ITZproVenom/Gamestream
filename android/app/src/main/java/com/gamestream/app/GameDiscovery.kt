package com.gamestream.app

enum class DiscoveryMode(val title: String, val shelfTitle: String) {
    MULTIPLAYER("Multiplayer", "Play with others"),
    CO_OP("Co-op", "Co-op nights"),
    SOLO("Solo", "Solo stories"),
    QUICK_PLAY("Quick play", "Quick play"),
    GAME_PASS("Game Pass", "On Game Pass");
}

object GameDiscovery {
    fun modes(id: String): Set<DiscoveryMode> = when (id.uppercase()) {
        "9NNX1VVR3KNQ" -> setOf(DiscoveryMode.MULTIPLAYER, DiscoveryMode.GAME_PASS)
        "9NP1P1WFS0LB" -> setOf(DiscoveryMode.MULTIPLAYER, DiscoveryMode.CO_OP, DiscoveryMode.GAME_PASS)
        "BT5P2X999VH2" -> setOf(DiscoveryMode.MULTIPLAYER, DiscoveryMode.QUICK_PLAY)
        "9NXP44L49SHJ" -> setOf(DiscoveryMode.MULTIPLAYER, DiscoveryMode.CO_OP, DiscoveryMode.GAME_PASS)
        "9P2N57MC619K" -> setOf(DiscoveryMode.MULTIPLAYER, DiscoveryMode.CO_OP, DiscoveryMode.GAME_PASS)
        "BQ1TN1T79V9K" -> setOf(DiscoveryMode.MULTIPLAYER, DiscoveryMode.QUICK_PLAY)
        "9N201KQXS5BM" -> setOf(DiscoveryMode.MULTIPLAYER, DiscoveryMode.QUICK_PLAY)
        "9NCJSXWZTP88" -> setOf(DiscoveryMode.SOLO, DiscoveryMode.GAME_PASS)
        "9PJTHRNVH62H" -> setOf(DiscoveryMode.CO_OP, DiscoveryMode.GAME_PASS, DiscoveryMode.SOLO)
        "9NKV34XDW014" -> setOf(DiscoveryMode.MULTIPLAYER, DiscoveryMode.CO_OP)
        "9NBR2VXT87SJ" -> setOf(DiscoveryMode.SOLO, DiscoveryMode.GAME_PASS)
        "9NFTC552K3GJ" -> setOf(DiscoveryMode.SOLO, DiscoveryMode.QUICK_PLAY, DiscoveryMode.GAME_PASS)
        "9NX6K9HN4F4K" -> setOf(DiscoveryMode.SOLO, DiscoveryMode.GAME_PASS)
        "9N8CD0XZKLP4" -> setOf(DiscoveryMode.SOLO, DiscoveryMode.GAME_PASS)
        "9NB0115C9WNM" -> setOf(DiscoveryMode.CO_OP, DiscoveryMode.SOLO, DiscoveryMode.GAME_PASS)
        else -> setOf(DiscoveryMode.GAME_PASS)
    }

    fun games(mode: DiscoveryMode): List<CatalogGame> =
        GameCatalog.games.filter { mode in modes(it.id) }

    fun shelves(): List<Pair<String, List<CatalogGame>>> =
        DiscoveryMode.entries.mapNotNull { mode ->
            val items = games(mode)
            if (items.size >= 2) mode.shelfTitle to items else null
        }

    fun fromTitle(title: String): DiscoveryMode? =
        DiscoveryMode.entries.firstOrNull { it.title == title }
}
