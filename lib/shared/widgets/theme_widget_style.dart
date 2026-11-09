import 'package:flutter/material.dart';

Widget styleThemeWidget(Widget widget, {Color? color, double? radius}) {
  if (color != null && widget is Theme)
    return Theme(
      key: widget.key,
      data: widget.data,
      child: styleThemeWidget(widget.child, color: color, radius: radius),
    );
  if (color != null && widget is ClipRRect)
    return ClipRRect(
      key: widget.key,
      borderRadius: widget.borderRadius,
      clipBehavior: widget.clipBehavior,
      child: styleThemeWidget(widget.child!, color: color, radius: radius),
    );
  if (color != null && widget is BackdropFilter)
    return BackdropFilter(
      key: widget.key,
      filter: widget.filter,
      blendMode: widget.blendMode,
      enabled: widget.enabled,
      child: styleThemeWidget(widget.child!, color: color, radius: radius),
    );
  if (color != null &&
      widget is DecoratedBox &&
      widget.decoration is BoxDecoration) {
    final old = widget.decoration as BoxDecoration;
    return DecoratedBox(
      key: widget.key,
      position: widget.position,
      decoration: BoxDecoration(
        color: color,
        border: old.border,
        borderRadius: old.borderRadius,
        boxShadow: old.boxShadow,
        shape: old.shape,
      ),
      child: widget.child,
    );
  }
  if (widget is Card && (color != null || radius != null))
    return Card(
      key: widget.key,
      color: color ?? widget.color,
      shadowColor: widget.shadowColor,
      surfaceTintColor: Colors.transparent,
      elevation: widget.elevation,
      shape: radius == null
          ? widget.shape
          : RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      margin: widget.margin,
      clipBehavior: widget.clipBehavior,
      semanticContainer: widget.semanticContainer,
      borderOnForeground: widget.borderOnForeground,
      child: widget.child,
    );
  final border = radius == null
      ? null
      : RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));
  if (widget is Container && (color != null || radius != null)) {
    final old = widget.decoration;
    final decoration = old is BoxDecoration
        ? BoxDecoration(
            color: color ?? old.color,
            gradient: color == null ? old.gradient : null,
            image: old.image,
            border: old.border,
            borderRadius: radius == null
                ? old.borderRadius
                : BorderRadius.circular(radius),
            boxShadow: old.boxShadow,
            backgroundBlendMode: old.backgroundBlendMode,
            shape: radius == null ? old.shape : BoxShape.rectangle,
          )
        : (old ??
              BoxDecoration(
                color: color ?? widget.color,
                borderRadius: radius == null
                    ? null
                    : BorderRadius.circular(radius),
              ));
    return Container(
      key: widget.key,
      alignment: widget.alignment,
      padding: widget.padding,
      color: null,
      decoration: decoration,
      foregroundDecoration: widget.foregroundDecoration,
      constraints: widget.constraints,
      margin: widget.margin,
      transform: widget.transform,
      transformAlignment: widget.transformAlignment,
      clipBehavior: widget.clipBehavior,
      child: widget.child,
    );
  }
  if (widget is ButtonStyleButton) {
    final filled = widget is FilledButton || widget is ElevatedButton;
    final style = (widget.style ?? const ButtonStyle()).copyWith(
      shape: border == null ? null : WidgetStatePropertyAll(border),
      backgroundColor: color != null && filled
          ? WidgetStatePropertyAll(color)
          : null,
      foregroundColor: color == null
          ? null
          : WidgetStatePropertyAll(
              filled
                  ? (ThemeData.estimateBrightnessForColor(color) ==
                            Brightness.dark
                        ? Colors.white
                        : Colors.black)
                  : color,
            ),
    );
    if (widget is TextButton)
      return TextButton(
        key: widget.key,
        onPressed: widget.onPressed,
        onLongPress: widget.onLongPress,
        onHover: widget.onHover,
        onFocusChange: widget.onFocusChange,
        style: style,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        clipBehavior: widget.clipBehavior,
        statesController: widget.statesController,
        child: widget.child!,
      );
    if (widget is FilledButton)
      return FilledButton(
        key: widget.key,
        onPressed: widget.onPressed,
        onLongPress: widget.onLongPress,
        onHover: widget.onHover,
        onFocusChange: widget.onFocusChange,
        style: style,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        clipBehavior: widget.clipBehavior,
        statesController: widget.statesController,
        child: widget.child!,
      );
    if (widget is OutlinedButton)
      return OutlinedButton(
        key: widget.key,
        onPressed: widget.onPressed,
        onLongPress: widget.onLongPress,
        onHover: widget.onHover,
        onFocusChange: widget.onFocusChange,
        style: style,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        clipBehavior: widget.clipBehavior,
        statesController: widget.statesController,
        child: widget.child!,
      );
    if (widget is ElevatedButton)
      return ElevatedButton(
        key: widget.key,
        onPressed: widget.onPressed,
        onLongPress: widget.onLongPress,
        onHover: widget.onHover,
        onFocusChange: widget.onFocusChange,
        style: style,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        clipBehavior: widget.clipBehavior,
        statesController: widget.statesController,
        child: widget.child!,
      );
  }
  return widget;
}
