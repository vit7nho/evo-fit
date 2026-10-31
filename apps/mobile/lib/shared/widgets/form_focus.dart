import 'package:flutter/widgets.dart';

/// Valida o formulário e, havendo erro, leva o foco ao primeiro campo inválido.
///
/// Sem isso, o foco fica no botão de enviar e o TalkBack não anuncia nada: o
/// usuário não sabe que o envio falhou nem onde está o problema. Com o foco no
/// campo, o leitor de tela lê o rótulo e a mensagem de erro, e a tela rola até ele.
bool validateAndFocusFirstError(FormState form) {
  final invalid = form.validateGranularly();
  if (invalid.isEmpty) return true;

  FocusNode? node;
  void visit(Element element) {
    if (node != null) return;
    final widget = element.widget;
    if (widget is EditableText) {
      node = widget.focusNode;
      return;
    }
    element.visitChildren(visit);
  }

  // A ordem do conjunto é a ordem dos campos na tela.
  (invalid.first.context as Element).visitChildren(visit);
  node?.requestFocus();
  return false;
}
