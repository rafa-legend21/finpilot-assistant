String categoryLabel(String category, String language) {
  final labels = switch (category) {
    'grocery' => ('杂货', 'Groceries', 'Épicerie'),
    'dining' => ('餐饮', 'Dining', 'Restauration'),
    'transportation' => ('交通', 'Transportation', 'Transport'),
    'shopping' => ('购物', 'Shopping', 'Achats'),
    'entertainment' => ('娱乐', 'Entertainment', 'Loisirs'),
    'housing' => ('住房', 'Housing', 'Logement'),
    'utilities' => ('水电等费用', 'Utilities', 'Services publics'),
    'healthcare' => ('医疗', 'Healthcare', 'Santé'),
    'travel' => ('旅行', 'Travel', 'Voyage'),
    'education' => ('教育', 'Education', 'Éducation'),
    'subscription' => ('订阅', 'Subscription', 'Abonnement'),
    'investment' => ('投资', 'Investment', 'Investissement'),
    'transfer' => ('转账', 'Transfer', 'Virement'),
    'income' => ('收入', 'Income', 'Revenu'),
    'other' => ('其他', 'Other', 'Autre'),
    _ => (category, category, category),
  };
  return switch (language) {
    'zh' => labels.$1,
    'fr' => labels.$3,
    _ => labels.$2,
  };
}
