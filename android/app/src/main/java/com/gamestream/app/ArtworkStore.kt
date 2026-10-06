package com.gamestream.app

object ArtworkStore {
    fun urlFor(game: CatalogGame): String? = game.posterUrl
    fun urlFor(productId: String): String? = GameCatalog.find(productId)?.posterUrl
}
