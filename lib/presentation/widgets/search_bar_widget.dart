import 'package:flutter/material.dart';

class SearchBarWidget extends StatefulWidget {
  const SearchBarWidget({
    super.key,
    required this.controller,
    required this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.focusNode,
    this.autofocus = false,
    this.hintText = 'Canciones, artistas o álbumes',
    this.trailing,
    this.onVoiceSearch,
    this.isListening = false,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final FocusNode? focusNode;
  final bool autofocus;
  final String hintText;
  final Widget? trailing;
  final VoidCallback? onVoiceSearch;
  final bool isListening;

  @override
  State<SearchBarWidget> createState() => _SearchBarWidgetState();
}

class _SearchBarWidgetState extends State<SearchBarWidget> {
  FocusNode? _ownedFocusNode;
  FocusNode get _focusNode =>
      widget.focusNode ?? (_ownedFocusNode ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(covariant SearchBarWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _ownedFocusNode)?.removeListener(_onFocusChanged);
      _focusNode.addListener(_onFocusChanged);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    widget.controller.removeListener(_onTextChanged);
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  void _onFocusChanged() => setState(() {});
  void _onTextChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[
      if (widget.onVoiceSearch != null)
        _VoiceSearchButton(
          listening: widget.isListening,
          onPressed: widget.onVoiceSearch!,
        ),
      if (widget.trailing != null) widget.trailing!,
      if (widget.controller.text.isNotEmpty)
        IconButton(
          tooltip: 'Limpiar búsqueda',
          onPressed: () {
            widget.controller.clear();
            widget.onChanged('');
          },
          icon: const Icon(Icons.close_rounded),
        ),
    ];
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: _focusNode.hasFocus
            ? [
                BoxShadow(
                  color: Theme.of(context).colorScheme.primary
                      .withValues(alpha: .12),
                  blurRadius: 18,
                  offset: const Offset(0, 5),
                ),
              ]
            : const [],
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        onTap: widget.onTap,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: widget.hintText,
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: actions.isEmpty
              ? null
              : Row(mainAxisSize: MainAxisSize.min, children: actions),
          contentPadding: const EdgeInsets.symmetric(vertical: 18),
        ),
      ),
    );
  }
}

class _VoiceSearchButton extends StatelessWidget {
  const _VoiceSearchButton({required this.listening, required this.onPressed});

  final bool listening;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: listening ? 'Detener dictado' : 'Buscar por voz',
      onPressed: onPressed,
      icon: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: listening
              ? colors.primary.withValues(alpha: .2)
              : Colors.transparent,
        ),
        child: Icon(
          listening ? Icons.mic_rounded : Icons.mic_none_rounded,
          color: listening ? colors.primary : null,
        ),
      ),
    );
  }
}
