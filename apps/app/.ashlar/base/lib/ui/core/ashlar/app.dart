// Ashlar UI: the app shell. Copied into your app by `ashlar init`; it is yours to change.
// Use it in place of MaterialApp or CupertinoApp: it builds on WidgetsApp alone.

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'selection.dart';
import 'theme.dart';

/// Which theme an [AshlarApp] shows.
enum AshlarThemeMode { system, light, dark }

/// The root of an Ashlar UI app: navigation from [WidgetsApp], and the theme, text and
/// icon defaults every component reads.
class AshlarApp extends StatelessWidget {
  const AshlarApp({
    super.key,
    this.home,
    this.routes = const {},
    this.initialRoute,
    this.onGenerateRoute,
    this.navigatorKey,
    this.title = '',
    this.theme = const AshlarThemeData.light(),
    this.darkTheme = const AshlarThemeData.dark(),
    this.themeMode = AshlarThemeMode.system,
    this.locale,
    this.supportedLocales = const [Locale('en', 'US')],
    this.localizationsDelegates,
    this.builder,
    this.selectable,
  }) : routerConfig = null;

  /// An app whose pages come from a router, such as go_router's GoRouter, given as
  /// [routerConfig]. The router builds the pages, so they are not made selectable the
  /// way [AshlarPageRoute] makes them: wrap a page in a SelectionArea where its text
  /// should be.
  ///
  /// ```dart
  /// AshlarApp.router(routerConfig: GoRouter(routes: [...]), theme: appTheme)
  /// ```
  const AshlarApp.router({
    super.key,
    required RouterConfig<Object> this.routerConfig,
    this.title = '',
    this.theme = const AshlarThemeData.light(),
    this.darkTheme = const AshlarThemeData.dark(),
    this.themeMode = AshlarThemeMode.system,
    this.locale,
    this.supportedLocales = const [Locale('en', 'US')],
    this.localizationsDelegates,
    this.builder,
    this.selectable,
  }) : home = null,
       routes = const {},
       initialRoute = null,
       onGenerateRoute = null,
       navigatorKey = null;

  /// Where pages come from, for [AshlarApp.router]; null for an app of [home] and [routes].
  final RouterConfig<Object>? routerConfig;

  /// The first page, at '/'.
  final Widget? home;

  /// Pages by name, for Navigator.pushNamed.
  final Map<String, WidgetBuilder> routes;

  /// The page to open on, by name, instead of home.
  final String? initialRoute;

  /// Makes a page for a name not in routes.
  final RouteFactory? onGenerateRoute;

  /// The navigator's key, to push pages from outside the widget tree.
  final GlobalKey<NavigatorState>? navigatorKey;

  /// The app's name, for the task switcher and the browser tab.
  final String title;

  /// The light theme.
  final AshlarThemeData theme;

  /// The dark theme.
  final AshlarThemeData darkTheme;

  /// Light, dark, or as the device is set.
  final AshlarThemeMode themeMode;

  /// The app's language and region, when not the device's.
  final Locale? locale;

  /// The languages and regions the app is written for.
  final Iterable<Locale> supportedLocales;

  /// Where translated words come from.
  final Iterable<LocalizationsDelegate<dynamic>>? localizationsDelegates;

  /// Wraps every page: for providers the whole app needs.
  final TransitionBuilder? builder;

  /// Whether text on the app's pages can be selected and copied, as on a web page.
  /// Controls are left out: dragging over a button never selects its label. Null means
  /// yes on the web and the desktop, and no on iOS and Android, where apps do not do it.
  final bool? selectable;

  bool get _selectable =>
      selectable ??
      (kIsWeb ||
          switch (defaultTargetPlatform) {
            TargetPlatform.iOS ||
            TargetPlatform.android ||
            TargetPlatform.fuchsia => false,
            _ => true,
          });

  AshlarThemeData _themeFor(BuildContext context) => switch (themeMode) {
    AshlarThemeMode.light => theme,
    AshlarThemeMode.dark => darkTheme,
    AshlarThemeMode.system =>
      MediaQuery.platformBrightnessOf(context) == Brightness.dark
          ? darkTheme
          : theme,
  };

  /// The theme, text and icon defaults around every page.
  Widget _wrap(BuildContext context, Widget? child) {
    final data = _themeFor(context);
    Widget page = AshlarTheme(
      data: data,
      child: DefaultTextStyle(
        style: data.text.sm.copyWith(color: data.colors.foreground),
        child: IconTheme(
          data: IconThemeData(color: data.colors.foreground, size: 16),
          child: ScrollConfiguration(
            behavior: const _AshlarScrollBehavior(),
            child: ColoredBox(
              color: data.colors.background,
              child: _SelectionDefault(
                selectable: _selectable,
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );
    if (builder != null) page = builder!(context, page);
    return page;
  }

  @override
  Widget build(BuildContext context) {
    final data = _themeFor(context);
    final textStyle = data.text.sm.copyWith(color: data.colors.foreground);
    if (routerConfig case final config?) {
      return WidgetsApp.router(
        routerConfig: config,
        title: title,
        color: data.colors.primary,
        locale: locale,
        supportedLocales: supportedLocales,
        localizationsDelegates: localizationsDelegates,
        debugShowCheckedModeBanner: false,
        textStyle: textStyle,
        builder: _wrap,
      );
    }
    return WidgetsApp(
      navigatorKey: navigatorKey,
      home: home,
      routes: routes,
      initialRoute: initialRoute,
      onGenerateRoute: onGenerateRoute,
      title: title,
      color: data.colors.primary,
      locale: locale,
      supportedLocales: supportedLocales,
      localizationsDelegates: localizationsDelegates,
      debugShowCheckedModeBanner: false,
      textStyle: textStyle,
      pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) =>
          AshlarPageRoute<T>(settings: settings, builder: builder),
      builder: _wrap,
    );
  }
}

/// Whether the app's pages are selectable, for [AshlarPageRoute] to read.
class _SelectionDefault extends InheritedWidget {
  const _SelectionDefault({required this.selectable, required super.child});

  final bool selectable;

  @override
  bool updateShouldNotify(_SelectionDefault old) =>
      old.selectable != selectable;
}

/// A page that fades and rises a little as it opens.
class AshlarPageRoute<T> extends PageRouteBuilder<T> {
  /// [selectable] null follows the app: [AshlarApp.selectable].
  AshlarPageRoute({
    required WidgetBuilder builder,
    bool? selectable,
    super.settings,
  }) : super(
         transitionDuration: const Duration(milliseconds: 220),
         reverseTransitionDuration: const Duration(milliseconds: 180),
         pageBuilder: (context, animation, secondary) {
           final on =
               selectable ??
               context
                   .dependOnInheritedWidgetOfExactType<_SelectionDefault>()
                   ?.selectable ??
               false;
           if (!on) return builder(context);
           // Each page is its own region, inside the Navigator's Overlay that its handles
           // and menu float in.
           final colors = AshlarTheme.of(context).colors;
           return SelectableRegion(
             selectionControls: AshlarSelectionControls(colors.foreground),
             contextMenuBuilder: (context, state) => AshlarSelectionMenu(
               anchors: state.contextMenuAnchors,
               items: state.contextMenuButtonItems,
             ),
             child: Builder(builder: builder),
           );
         },
         transitionsBuilder: (context, animation, secondary, child) {
           final curved = CurvedAnimation(
             parent: animation,
             curve: Curves.easeOutCubic,
           );
           return FadeTransition(
             opacity: curved,
             child: SlideTransition(
               position: Tween(
                 begin: const Offset(0, .02),
                 end: Offset.zero,
               ).animate(curved),
               child: child,
             ),
           );
         },
       );
}

/// Scrolling without Material's stretch or glow.
class _AshlarScrollBehavior extends ScrollBehavior {
  const _AshlarScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}
