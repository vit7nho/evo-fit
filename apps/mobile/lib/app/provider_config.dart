/// Política de nova tentativa dos providers do app.
///
/// O Riverpod 3 refaz automaticamente providers que falham, com backoff crescente. Isso
/// atrasa a exibição do estado de erro por vários segundos e repete chamadas que alteram
/// dados. No EvoFit a nova tentativa é sempre explícita (botão "Tentar novamente").
Duration? noAutomaticRetry(int retryCount, Object error) => null;
