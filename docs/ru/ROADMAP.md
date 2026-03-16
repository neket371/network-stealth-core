# roadmap

этот roadmap — публичное направление, а не жёсткое обещание поставки.

## текущий baseline

текущая strongest-direct линия `v7` закрепляет:

- минимальный strongest-direct install
- policy-driven managed state через `policy.json`
- клиентский инвентарь schema v3 с `recommended`, `rescue` и `emergency`
- canonical raw xray exports и canary bundle
- сохранённые self-check history и field measurement summary
- adaptive repair и `update --replan`

## ближайшие приоритеты

1. ещё сильнее упростить импорт field reports от удалённых canary-операторов
2. улучшить поддержку catalog и качество provider-family diversity
3. сделать compare и summarize выводы более понятными для операторов
4. держать двуязычные docs и release metadata идеально синхронными

## среднесрочное направление

- более сильные operator-tools для импорта field data и просмотра долгосрочных трендов
- более безопасная автоматизация retire/rotation для повторно слабых конфигов
- более богатые capability notes для внешних клиентов, когда появится честная поддержка

## пока вне scope

- добавление новых вопросов в normal install path
- возврат legacy transport как активного продуктового пути
- фейковые compatibility templates для unsupported strongest-direct features
- широкие multi-os обещания без ci coverage
- обязательные cdn или fleet-management слои в core path
