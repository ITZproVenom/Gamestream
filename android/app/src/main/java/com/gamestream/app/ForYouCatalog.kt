package com.gamestream.app

object ForYouCatalog {
    fun forYou(favorites: List<CatalogGame>, recents: List<CatalogGame>, limit: Int = 10): List<CatalogGame> {
        val seen = (recents + favorites).map { it.id }.toSet()
        val weights = mutableMapOf<String, Int>()
        recents.take(6).forEach { weights[it.genre] = (weights[it.genre] ?: 0) + 3 }
        favorites.take(8).forEach { weights[it.genre] = (weights[it.genre] ?: 0) + 2 }
        if (weights.isEmpty()) return GameCatalog.featured.take(limit)
        return GameCatalog.games
            .filter { it.id !in seen }
            .map { game ->
                var score = weights[game.genre] ?: 0
                if (game.featured) score += 1
                game to score
            }
            .sortedWith(compareByDescending<Pair<CatalogGame, Int>> { it.second }.thenBy { it.first.title })
            .take(limit)
            .map { it.first }
    }

    fun becauseYouPlayed(recents: List<CatalogGame>, limitPerShelf: Int = 6): List<Pair<String, List<CatalogGame>>> {
        val used = recents.map { it.id }.toMutableSet()
        val rows = mutableListOf<Pair<String, List<CatalogGame>>>()
        recents.take(3).forEach { seed ->
            val picks = GameCatalog.related(seed, limitPerShelf + 4).filter { it.id !in used }.take(limitPerShelf)
            if (picks.size >= 2) {
                picks.forEach { used.add(it.id) }
                rows += "Because you played ${seed.title}" to picks
            }
        }
        return rows
    }

    val genreNames: List<String> =
        listOf("Racing", "Shooter", "Action", "Adventure", "Sandbox", "RPG", "Survival", "Platformer")
}
