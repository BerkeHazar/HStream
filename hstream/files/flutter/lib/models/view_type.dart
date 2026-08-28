enum ViewType { all, categories, favorites, history, settings }

String viewTypeToString(ViewType vw) {
  switch (vw) {
    case ViewType.all:
      return "Tümü";
    case ViewType.categories:
      return "Kategoriler";
    case ViewType.favorites:
      return "Favoriler";
    case ViewType.history:
      return "Geçmiş";
    default:
      return "Tümü";
  }
}
