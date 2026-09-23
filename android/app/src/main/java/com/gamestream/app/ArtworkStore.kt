package com.gamestream.app

object ArtworkStore {
    fun urlFor(game: CatalogGame): String? = game.posterUrl
    fun urlFor(productId: String): String? = GameCatalog.games.firstOrNull { it.id == productId }?.posterUrl
    fun url(productId: String): String? = urlFor(productId)
}
