package com.gamestream.app

data class CatalogGame(
    val id: String,
    val slug: String,
    val title: String,
    val tagline: String,
    val genre: String,
    val provider: String = "Xbox Cloud",
    val featured: Boolean = false,
    val accent: Long = 0xFF4361EE
) {
    val catalogUrl: String
        get() = "https://www.xbox.com/play/games/$slug/$id"
    val launchUrl: String
        get() = "https://www.xbox.com/play/launch/$slug/$id"
}

object GameCatalog {
    val games: List<CatalogGame> = listOf(
        CatalogGame("9PNJ1RJL8SL9", "forza-horizon-5", "Forza Horizon 5", "Open-world racing across Mexico", "Racing", featured = true, accent = 0xFFE85D04),
        CatalogGame("9NP1P1W3J5C6", "halo-infinite", "Halo Infinite", "Master Chief returns to the ring", "Shooter", featured = true, accent = 0xFF2D6A4F),
        CatalogGame("9N87K6P39X81", "fortnite", "Fortnite", "Battle Royale, Zero Build, and more", "Action", featured = true, accent = 0xFF5A189A),
        CatalogGame("9NBLGGH2JHXJ", "minecraft", "Minecraft", "Build, explore, survive", "Sandbox", featured = true, accent = 0xFF40916C),
        CatalogGame("9NN3HCKW5TPC", "sea-of-thieves", "Sea of Thieves", "Sail, plunder, and tell tall tales", "Adventure", featured = true, accent = 0xFF0077B6),
        CatalogGame("9NBLGGH32QM8", "roblox", "Roblox", "Millions of player-created worlds", "Sandbox", accent = 0xFFE63946),
        CatalogGame("9NBLGGH4R315", "call-of-duty", "Call of Duty", "Multiplayer and Warzone on the cloud", "Shooter", accent = 0xFF6C757D),
        CatalogGame("9MT8ND8BP6J2", "starfield", "Starfield", "Bethesda's jump into the stars", "RPG", accent = 0xFF3D405B),
        CatalogGame("9NBLGGH42THS", "grounded", "Grounded", "Survive the backyard, ant-sized", "Survival", accent = 0xFF588157),
        CatalogGame("9N9J38LPVSM3", "palworld", "Palworld", "Catch pals, build bases, survive", "Survival", accent = 0xFF00B4D8),
        CatalogGame("9NBLGGH43KHL", "psychonauts-2", "Psychonauts 2", "A trip through wild minds", "Adventure", accent = 0xFF9B5DE5),
        CatalogGame("9PMQDM08SNK9", "hi-fi-rush", "Hi-Fi Rush", "Rhythm-action in a music studio", "Action", accent = 0xFFF72585),
        CatalogGame("9N1CD16C2NQ0", "pentiment", "Pentiment", "A medieval mystery in ink", "Adventure", accent = 0xFFBC6C25),
        CatalogGame("9N2S0C936B3P", "ori-and-the-will-of-the-wisps", "Ori and the Will of the Wisps", "A beautiful Metroidvania journey", "Platformer", accent = 0xFF4CC9F0),
        CatalogGame("9NBLGGH1Z6FQ", "cuphead", "Cuphead", "Run-and-gun with jazz-age style", "Action", accent = 0xFFD00000)
    )

    val featured: List<CatalogGame> get() = games.filter { it.featured }

    fun matches(query: String): List<CatalogGame> {
        val q = query.trim()
        if (q.isEmpty()) return games
        val slugQ = q.replace(" ", "-")
        return games.filter {
            it.title.contains(q, ignoreCase = true) ||
                it.genre.contains(q, ignoreCase = true) ||
                it.tagline.contains(q, ignoreCase = true) ||
                it.slug.contains(slugQ, ignoreCase = true)
        }
    }

    fun related(to: CatalogGame, limit: Int = 6): List<CatalogGame> {
        val same = games.filter { it.genre == to.genre && it.id != to.id }
        return if (same.size >= 2) same.take(limit) else games.filter { it.id != to.id }.take(limit)
    }
}
