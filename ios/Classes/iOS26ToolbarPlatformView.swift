import UIKit
import Flutter

/// Factory for creating iOS 26 native UIToolbar platform views
class iOS26ToolbarFactory: NSObject, FlutterPlatformViewFactory {
    private var messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        return iOS26ToolbarPlatformView(
            frame: frame,
            viewIdentifier: viewId,
            arguments: args,
            binaryMessenger: messenger
        )
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}

/// Native iOS 26 UIToolbar platform view
class iOS26ToolbarPlatformView: NSObject, FlutterPlatformView {
    private var _containerView: UIView
    private var _toolbar: UIToolbar
    private var _titleLabel: UILabel? // Separate title label to avoid Liquid Glass effect
    private var _viewId: Int64
    private var _channel: FlutterMethodChannel

    init(
        frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        binaryMessenger messenger: FlutterBinaryMessenger
    ) {
        _containerView = UIView(frame: frame)
        _toolbar = UIToolbar()
        _viewId = viewId
        _channel = FlutterMethodChannel(
            name: "adaptive_platform_ui/ios26_toolbar_\(viewId)",
            binaryMessenger: messenger
        )

        super.init()

        // Disable implicit animations for the container and toolbar
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        // Clip the container view to prevent shadow/effects from bleeding out
        // _containerView.clipsToBounds = true
        // _containerView.layer.masksToBounds = true

        // Add toolbar to container
        _containerView.addSubview(_toolbar)
        
        // Remove any shadow from toolbar
        // _toolbar.clipsToBounds = true
        // _toolbar.layer.masksToBounds = true
        // _toolbar.layer.shadowOpacity = 0
        // _toolbar.layer.shadowRadius = 0
        // _toolbar.layer.shadowOffset = .zero

        // Setup constraints for toolbar with SafeArea
        _toolbar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            _toolbar.topAnchor.constraint(equalTo: _containerView.safeAreaLayoutGuide.topAnchor),
            _toolbar.leadingAnchor.constraint(equalTo: _containerView.leadingAnchor),
            _toolbar.trailingAnchor.constraint(equalTo: _containerView.trailingAnchor),
            _toolbar.bottomAnchor.constraint(equalTo: _containerView.bottomAnchor)
        ])

        // iOS 26+ Liquid Glass appearance with blur effect
        if #available(iOS 13.0, *) {
            let appearance = UIToolbarAppearance()

            // Use transparent background with blur (Liquid Glass effect)
            appearance.configureWithTransparentBackground()
            appearance.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.8)
            
            // Remove shadow image and line to prevent visual artifacts
            // appearance.shadowImage = nil
            // appearance.shadowColor = .clear

            // Apply system material blur effect for iOS 26+
            if #available(iOS 26.0, *) {
                appearance.backgroundEffect = UIBlurEffect(style: .systemMaterial)
            } else {
                // Fallback for older iOS versions
                appearance.backgroundEffect = UIBlurEffect(style: .systemMaterial)
            }

            _toolbar.standardAppearance = appearance
            if #available(iOS 15.0, *) {
                _toolbar.scrollEdgeAppearance = appearance
                _toolbar.compactAppearance = appearance
            }
        }
        
        // Remove the default toolbar shadow/separator line
        _toolbar.setShadowImage(UIImage(), forToolbarPosition: .any)

        // Enable blur and translucency
        _toolbar.isTranslucent = true

        // Parse arguments
        if let params = args as? [String: Any] {
            configureToolbar(params)
        }
        
        // End the CATransaction to commit all changes without animation
        CATransaction.commit()

        // Setup method channel
        _channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
            self?.handleMethodCall(call, result: result)
        }
    }

    func view() -> UIView {
        return _containerView
    }

    private func configureToolbar(_ params: [String: Any]) {
        var items: [UIBarButtonItem] = []

        let hasTitle = params["title"] as? String != nil && !(params["title"] as? String ?? "").isEmpty
        let hasActions = params["actions"] as? [[String: Any]] != nil && !(params["actions"] as? [[String: Any]] ?? []).isEmpty
        let hasLeading = params["leading"] != nil
        let centerTitle = (params["centerTitle"] as? Bool) ?? true // Default to centered for iOS
        
        // Check if Flutter has a custom leading widget overlayed
        // If so, we need to reserve space for it instead of showing native leading
        let hasCustomLeadingWidget = (params["hasLeadingWidget"] as? Bool) ?? false
        let leadingWidgetWidth = (params["leadingWidgetWidth"] as? CGFloat) ?? 44.0
        
        // Add space for custom Flutter leading widget if provided
        if hasCustomLeadingWidget {
            // Add a fixed space to account for the custom Flutter leading widget
            if #available(iOS 16.0, *) {
                items.append(.fixedSpace(leadingWidgetWidth + 8)) // Widget width + padding
            } else {
                // For older iOS, use a clear button as spacer
                let spacer = UIBarButtonItem(
                    title: "",
                    style: .plain,
                    target: nil,
                    action: nil
                )
                spacer.isEnabled = false
                spacer.width = leadingWidgetWidth + 8
                items.append(spacer)
            }
        }

        // Leading button (left side) - only if no custom Flutter leading widget
        if !hasCustomLeadingWidget, let leadingTitle = params["leading"] as? String {
            let leadingButton: UIBarButtonItem
            if leadingTitle.isEmpty {
                // Empty string = show back chevron icon
                leadingButton = UIBarButtonItem(
                    image: UIImage(systemName: "chevron.left"),
                    style: .plain,
                    target: self,
                    action: #selector(leadingTapped)
                )
            } else {
                // Show text
                leadingButton = UIBarButtonItem(
                    title: leadingTitle,
                    style: .plain,
                    target: self,
                    action: #selector(leadingTapped)
                )
            }
            items.append(leadingButton)
        }
        
        // Adjust hasLeading for layout purposes - true if native leading OR custom widget
        let effectiveHasLeading = hasLeading || hasCustomLeadingWidget

        // Actions - process and split into left/right groups if flexible spacer exists
        if let actions = params["actions"] as? [[String: Any]], !actions.isEmpty {
            var leftActions: [UIBarButtonItem] = []
            var rightActions: [UIBarButtonItem] = []
            var foundFlexibleSpacer = false

            for (index, action) in actions.enumerated() {
                var actionButton: UIBarButtonItem?

                if let actionTitle = action["title"] as? String {
                    actionButton = UIBarButtonItem(
                        title: actionTitle,
                        style: .plain,
                        target: self,
                        action: #selector(actionTapped(_:))
                    )
                    actionButton?.tag = index
                } else if let actionIcon = action["icon"] as? String {
                    actionButton = UIBarButtonItem(
                        image: UIImage(systemName: actionIcon),
                        style: .plain,
                        target: self,
                        action: #selector(actionTapped(_:))
                    )
                    actionButton?.tag = index
                }

                if let btn = actionButton {
                    if foundFlexibleSpacer {
                        rightActions.append(btn)
                    } else {
                        leftActions.append(btn)
                    }
                }

                // Check for spacer after this action
                if let spacerAfter = action["spacerAfter"] as? Int {
                    if spacerAfter == 1 { // Fixed space
                        if #available(iOS 16.0, *) {
                            if foundFlexibleSpacer {
                                rightActions.append(.fixedSpace(12))
                            } else {
                                leftActions.append(.fixedSpace(12))
                            }
                        }
                    } else if spacerAfter == 2 { // Flexible space - marks split point
                        foundFlexibleSpacer = true
                    }
                }
            }

            // If we found a flexible spacer, split actions into left/right groups
            if foundFlexibleSpacer {
                // Add left actions
                items.append(contentsOf: leftActions)

                items.append(UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil))

                // Note: Title is rendered as a separate UILabel overlay to avoid Liquid Glass effect
                // Just add flexible space here for layout (title will be centered)
                if hasTitle {
                    items.append(UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil))
                }

                // Add right actions
                items.append(contentsOf: rightActions)
            } else {
                // No flexible spacer - standard layout: Title on left, actions on right
                // Add spacing after leading button if it exists and there's a title
                if effectiveHasLeading && hasTitle && !hasCustomLeadingWidget {
                    if #available(iOS 16.0, *) {
                        items.append(.fixedSpace(8))
                    }
                }

                // Note: Title is rendered as a separate UILabel overlay to avoid Liquid Glass effect
                // No UIBarButtonItem needed for title here

                // Always add flexible space to push actions to the right
                items.append(UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil))

                // Add all actions to the right
                items.append(contentsOf: leftActions)
            }
        } else {
            // No actions
            // Add spacing after leading button if it exists and there's a title
            if effectiveHasLeading && hasTitle && !hasCustomLeadingWidget {
                if #available(iOS 16.0, *) {
                    items.append(.fixedSpace(8))
                }
            }

            // Note: Title is rendered as a separate UILabel overlay to avoid Liquid Glass effect
            // No UIBarButtonItem needed for title here

            // Always add flexible space to push everything to the left
            items.append(UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil))
        }

        _toolbar.items = items
        // Set toolbar items without animation to prevent icon scaling effect
        // CATransaction.begin()
        // CATransaction.setDisableActions(true)
        // _toolbar.setItems(items, animated: false)
        // CATransaction.commit()
        
        // Setup title label as separate overlay (not part of toolbar items)
        // This avoids the Liquid Glass bubble effect on iOS 26+
        _titleLabel?.removeFromSuperview()
        _titleLabel = nil
        
        if hasTitle, let title = params["title"] as? String, !title.isEmpty {
            let titleLabel = UILabel()
            titleLabel.text = title
            titleLabel.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
            
            // Use isDarkMode passed from Flutter to set the correct text color
            let isDarkMode = (params["isDarkMode"] as? Bool) ?? false
            titleLabel.textColor = isDarkMode ? UIColor.white : UIColor.black
            
            titleLabel.isUserInteractionEnabled = false
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            
            _containerView.addSubview(titleLabel)
            _titleLabel = titleLabel
            
            if centerTitle {
                // Center the title horizontally in the toolbar
                NSLayoutConstraint.activate([
                    titleLabel.centerXAnchor.constraint(equalTo: _containerView.centerXAnchor),
                    titleLabel.centerYAnchor.constraint(equalTo: _toolbar.centerYAnchor)
                ])
            } else {
                // Left-aligned title (positioned after leading button/widget)
                // Calculate leading offset based on whether there's a leading button or custom widget
                let hasCustomLeadingWidget = (params["hasLeadingWidget"] as? Bool) ?? false
                let leadingWidgetWidth = (params["leadingWidgetWidth"] as? CGFloat) ?? 44.0
                let hasNativeLeading = params["leading"] != nil
                
                // Determine left offset for title
                var leftOffset: CGFloat = 16 // Default padding
                if hasCustomLeadingWidget {
                    leftOffset = leadingWidgetWidth + 16 // Widget width + padding
                } else if hasNativeLeading {
                    leftOffset = 52 // Back button width + padding
                }
                
                NSLayoutConstraint.activate([
                    titleLabel.leadingAnchor.constraint(equalTo: _containerView.leadingAnchor, constant: leftOffset),
                    titleLabel.centerYAnchor.constraint(equalTo: _toolbar.centerYAnchor)
                ])
            }
        }
    }

    @objc private func leadingTapped() {
        _channel.invokeMethod("onLeadingTapped", arguments: nil)
    }

    @objc private func actionTapped(_ sender: UIBarButtonItem) {
        // Use the tag to get the action index
        let actionIndex = sender.tag
        _channel.invokeMethod("onActionTapped", arguments: ["index": actionIndex])
    }

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        result(FlutterMethodNotImplemented)
    }
}
