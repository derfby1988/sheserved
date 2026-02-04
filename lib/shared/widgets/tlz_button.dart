import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';

/// Custom Button for Sheserved
enum TlzButtonType { primary, secondary, outline, text }

enum TlzButtonSize { small, medium, large }

class TlzButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final TlzButtonType type;
  final TlzButtonSize size;
  final IconData? icon;
  final bool isLoading;
  final bool isFullWidth;
  final Color? backgroundColor;
  final Color? textColor;

  const TlzButton({
    super.key,
    required this.text,
    this.onPressed,
    this.type = TlzButtonType.primary,
    this.size = TlzButtonSize.medium,
    this.icon,
    this.isLoading = false,
    this.isFullWidth = false,
    this.backgroundColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: isFullWidth ? double.infinity : null,
      height: _getHeight(),
      child: _buildButton(),
    );
  }

  double _getHeight() {
    switch (size) {
      case TlzButtonSize.small:
        return 36;
      case TlzButtonSize.medium:
        return 48;
      case TlzButtonSize.large:
        return 56;
    }
  }

  EdgeInsets _getPadding() {
    switch (size) {
      case TlzButtonSize.small:
        return const EdgeInsets.symmetric(horizontal: 16, vertical: 8);
      case TlzButtonSize.medium:
        return const EdgeInsets.symmetric(horizontal: 24, vertical: 12);
      case TlzButtonSize.large:
        return const EdgeInsets.symmetric(horizontal: 32, vertical: 16);
    }
  }

  double _getFontSize() {
    switch (size) {
      case TlzButtonSize.small:
        return 12;
      case TlzButtonSize.medium:
        return 14;
      case TlzButtonSize.large:
        return 16;
    }
  }

  Widget _buildButton() {
    switch (type) {
      case TlzButtonType.primary:
        return _buildPrimaryButton();
      case TlzButtonType.secondary:
        return _buildSecondaryButton();
      case TlzButtonType.outline:
        return _buildOutlineButton();
      case TlzButtonType.text:
        return _buildTextButton();
    }
  }

  Widget _buildPrimaryButton() {
    return ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: backgroundColor ?? AppColors.primary,
        foregroundColor: textColor ?? AppColors.textOnPrimary,
        padding: _getPadding(),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 2,
      ),
      child: _buildContent(textColor ?? AppColors.textOnPrimary),
    );
  }

  Widget _buildSecondaryButton() {
    return ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: backgroundColor ?? AppColors.secondary,
        foregroundColor: textColor ?? AppColors.textOnSecondary,
        padding: _getPadding(),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 2,
      ),
      child: _buildContent(textColor ?? AppColors.textOnSecondary),
    );
  }

  Widget _buildOutlineButton() {
    return OutlinedButton(
      onPressed: isLoading ? null : onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: textColor ?? AppColors.primary,
        side: BorderSide(
          color: backgroundColor ?? AppColors.primary,
          width: 1.5,
        ),
        padding: _getPadding(),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: _buildContent(textColor ?? AppColors.primary),
    );
  }

  Widget _buildTextButton() {
    return TextButton(
      onPressed: isLoading ? null : onPressed,
      style: TextButton.styleFrom(
        foregroundColor: textColor ?? AppColors.primary,
        padding: _getPadding(),
      ),
      child: _buildContent(textColor ?? AppColors.primary),
    );
  }

  Widget _buildContent(Color color) {
    if (isLoading) {
      return SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      );
    }

    if (icon != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: _getFontSize() + 4),
          const SizedBox(width: 8),
          Text(
            text,
            style: AppTextStyles.button.copyWith(
              fontSize: _getFontSize(),
              color: color,
            ),
          ),
        ],
      );
    }

    return Text(
      text,
      style: AppTextStyles.button.copyWith(
        fontSize: _getFontSize(),
        color: color,
      ),
    );
  }
}
