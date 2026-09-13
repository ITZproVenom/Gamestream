package com.gamestream.app

data class CatalogGame(
    val id: String,
    val slug: String,
    val title: String,
    val tagline: String,
    val genre: String,
    val provider: String = "Xbox Cloud",
    val featured: Boolean = false,
    val accent: Long = 0xFF4361EE,
    val posterUrl: String? = null
) {
    val catalogUrl: String
        get() = "https://www.xbox.com/play/games/$slug/$id"
    val launchUrl: String
        get() = "https://www.xbox.com/play/launch/$slug/$id"
}

object GameCatalog {
    val games: List<CatalogGame> = listOf(
        CatalogGame("9NNX1VVR3KNQ", "forza-horizon-5", "Forza Horizon 5", "Open-world racing across Mexico", "Racing", featured = true, accent = 0xFFE85D04,
            posterUrl = "https://store-images.s-microsoft.com/image/apps.56329.13734397844529069.202e3fc9-37d6-4853-a58b-fabe504b71e8.b2447b97-7903-48de-8a49-9669d0495c4f"),
        CatalogGame("9NP1P1WFS0LB", "halo-infinite", "Halo Infinite", "Master Chief returns to the ring", "Shooter", featured = true, accent = 0xFF2D6A4F,
            posterUrl = "https://store-images.s-microsoft.com/image/apps.21536.13727851868390641.c9cc5f66-aff8-406c-af6b-440838730be0.68796bde-cbf5-4eaa-a299-011417041da6"),
        CatalogGame("BT5P2X999VH2", "fortnite", "Fortnite", "Battle Royale, Zero Build, and more", "Action", featured = true, accent = 0xFF5A189A,
            posterUrl = "https://store-images.s-microsoft.com/image/apps.19309.70702278257994163.7867c110-12f5-414d-88b4-e851aea24391.e7460671-6dd2-47d7-af59-71118b6d060c"),
        CatalogGame("9NXP44L49SHJ", "minecraft", "Minecraft", "Build, explore, survive", "Sandbox", featured = true, accent = 0xFF40916C,
            posterUrl = "https://store-images.s-microsoft.com/image/apps.808.14492077886571533.be42f4bd-887b-4430-8ed0-622341b4d2b0.c8274c53-105e-478b-9f4b-41b8088210a3"),
        CatalogGame("9P2N57MC619K", "sea-of-thieves", "Sea of Thieves", "Sail, plunder, and tell tall tales", "Adventure", featured = true, accent = 0xFF0077B6,
            posterUrl = "https://store-images.s-microsoft.com/image/apps.29206.14554784103656548.069efce3-9249-4074-a169-183b727043f8.03688f8c-edc0-416b-bebb-9d98a01c25f5"),
        CatalogGame("BQ1TN1T79V9K", "roblox", "Roblox", "Millions of player-created worlds", "Sandbox", accent = 0xFFE63946,
            posterUrl = "https://store-images.s-microsoft.com/image/apps.3683.68327322396008232.ddd32983-30da-4856-a0ef-70bb8840e88d.cb3ff148-2c1f-4b84-9eea-ff80eda50c2d"),
        CatalogGame("9N201KQXS5BM", "call-of-duty", "Call of Duty", "Multiplayer and Warzone on the cloud", "Shooter", accent = 0xFF6C757D,
            posterUrl = "https://store-images.s-microsoft.com/image/apps.30472.13966330883349940.9a0bbc3f-3231-4a17-ab16-55eb671f1755.d9aecc85-6637-4e56-a359-009944a02940"),
        CatalogGame("9NCJSXWZTP88", "starfield", "Starfield", "Bethesda's jump into the stars", "RPG", accent = 0xFF3D405B,
            posterUrl = "https://store-images.s-microsoft.com/image/apps.35187.13567343664224659.1eb6fdf9-8a0b-4344-a135-ab17dfa3c609.c83b6d6a-56c3-4c3f-8b31-456cfb21c3b7"),
        CatalogGame("9PJTHRNVH62H", "grounded", "Grounded", "Survive the backyard, ant-sized", "Survival", accent = 0xFF588157,
            posterUrl = "https://store-images.s-microsoft.com/image/apps.20293.14280109286674604.0f240f37-6e7f-43b4-bd81-aabc884bc103.16d2c3ac-d4fa-4540-8f7d-4c716d393513"),
        CatalogGame("9NKV34XDW014", "palworld", "Palworld", "Catch pals, build bases, survive", "Survival", accent = 0xFF00B4D8,
            posterUrl = "https://store-images.s-microsoft.com/image/apps.49778.13654268679289325.ececb946-5639-4e77-b347-9d188d4e7e02.9102215b-349a-4f6d-b9a3-2c14908481f1"),
        CatalogGame("9NBR2VXT87SJ", "psychonauts-2", "Psychonauts 2", "A trip through wild minds", "Adventure", accent = 0xFF9B5DE5,
            posterUrl = "https://store-images.s-microsoft.com/image/apps.59150.13578175979543723.424401c3-5602-4e35-abfc-c00f9156296a.99cd91cb-4b52-4353-b333-28a9e48f06fe"),
        CatalogGame("9NFTC552K3GJ", "hi-fi-rush", "Hi-Fi Rush", "Rhythm-action in a music studio", "Action", accent = 0xFFF72585,
            posterUrl = "https://store-images.s-microsoft.com/image/apps.54250.13592675470908447.79efa8be-9602-4911-867c-3b27d26ad414.5083e064-e3e9-4a23-bb10-684f7be75d15"),
        CatalogGame("9NX6K9HN4F4K", "pentiment", "Pentiment", "A medieval mystery in ink", "Adventure", accent = 0xFFBC6C25,
            posterUrl = "https://store-images.s-microsoft.com/image/apps.32118.14431229486160986.b3655366-4704-41dd-bb1b-0ea3f2425df6.808122ac-ca66-4ac7-8efc-134da0e929ca"),
        CatalogGame("9N8CD0XZKLP4", "ori-and-the-will-of-the-wisps", "Ori and the Will of the Wisps", "A beautiful Metroidvania journey", "Platformer", accent = 0xFF4CC9F0,
            posterUrl = "https://store-images.s-microsoft.com/image/apps.18799.14047496556148589.9fda5cef-7995-4dbb-a626-66d2ab3feb4f.1e167626-8b7d-47b4-9fe5-d06a43ac6677"),
        CatalogGame("9NB0115C9WNM", "cuphead", "Cuphead", "Run-and-gun with jazz-age style", "Action", accent = 0xFFD00000,
            posterUrl = "https://store-images.s-microsoft.com/image/apps.36678.13527301958862136.ffa8c20b-226b-443c-8d6c-cce51dca9945.7170663c-a4e2-46db-a81b-aa22c30d6d44")
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
