import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../../config/routing/guards/guards.dart';
import '../../../../config/routing/route_module.dart';
import '../../../../config/routing/route_spec.dart';
import '../../../../config/routing/transitions/route_transitions.dart';
import '../../../../core/constants/permissions.dart';
import '../../../../core/widgets/feature_placeholder.dart';

/// Access rule shared by the product and category trees: a signed-in user who
/// may view products.
///
/// Both trees read the same catalog, so one constant keeps them from drifting.
/// Child routes inherit it and can only tighten it.
const _canViewCatalog = CompositeGuard([
  AuthGuard(),
  PermissionGuard({Permissions.viewProducts}),
]);

/// Routes for the catalog tab: products and categories.
///
/// The two route trees sit under one tab, so they share a back stack, while
/// URLs stay honest: `/products/...` and `/categories/...`, not
/// `/catalog/products/...`.
///
/// ## Route map
///
/// | Route              | Path                           | Extra guard      | Navigator |
/// | ------------------ | ------------------------------ | ---------------- | --------- |
/// | [list]             | `/products`                    | none             | shell     |
/// | [create]           | `/products/new`                | `createProduct`  | root      |
/// | [detail]           | `/products/:productId`         | none             | shell     |
/// | [edit]             | `/products/:productId/edit`    | `updateProduct`  | shell     |
/// | [categories]       | `/categories`                  | none             | shell     |
/// | [categoryCreate]   | `/categories/new`              | `createProduct`  | root      |
/// | [categoryDetail]   | `/categories/:categoryId`      | none             | shell     |
/// | [categoryEdit]     | `/categories/:categoryId/edit` | `updateProduct`  | root      |
///
/// Every route also inherits the view guard from its tree's root.
///
/// ## Declaration order
///
/// In [routes], the literal `new` must be declared **before** `:productId`.
/// Otherwise go_router resolves `/products/new` as a product whose id is
/// `"new"`. `RouteRegistry.byLocation` ranks by literal segments for the same
/// reason.
///
/// ## Example
///
/// ```dart
/// // Navigate with typed specs, never path strings.
/// context.goTo(
///   CatalogRoutes.detail,
///   params: {CatalogRoutes.productId: 'sku_42'},
/// );
/// ```
///
/// See also:
///
/// * [RouteModule], the contract this class implements.
/// * [RouteSpec], which declares each route's path, guard and transition.
final class CatalogRoutes implements RouteModule {
  /// Creates the catalog route module.
  const CatalogRoutes();

  /// Path parameter key for a product id.
  static const productId = 'productId';

  /// Path parameter key for a category id.
  static const categoryId = 'categoryId';

  // ---------------------------------------------------------------------------
  // Products
  // ---------------------------------------------------------------------------

  /// The product list, `/products`. Root of the products tree.
  static const list = RouteSpec.root('/products', name: 'products', title: 'Products', guard: _canViewCatalog);

  /// The new-product form, `/products/new`.
  ///
  /// Opens full screen on the root navigator, above the navigation chrome.
  static const create = RouteSpec.child(
    list,
    'new',
    name: 'productNew',
    title: 'New product',
    guard: PermissionGuard({Permissions.createProduct}),
    transition: TransitionPreset.slideFromBottom,
    fullscreen: true,
  );

  /// A single product, `/products/:productId`.
  static const detail = RouteSpec.child(
    list,
    ':$productId',
    name: 'productDetail',
    title: 'Product',
    transition: TransitionPreset.slideFromRight,
  );

  /// The edit form for a product, `/products/:productId/edit`.
  static const edit = RouteSpec.child(
    detail,
    'edit',
    name: 'productEdit',
    title: 'Edit product',
    guard: PermissionGuard({Permissions.updateProduct}),
    transition: TransitionPreset.slideFromRight,
  );

  // ---------------------------------------------------------------------------
  // Categories
  // ---------------------------------------------------------------------------

  /// The category list, `/categories`. Root of the categories tree.
  static const categories = RouteSpec.root(
    '/categories',
    name: 'categories',
    title: 'Categories',
    guard: _canViewCatalog,
  );

  /// The new-category form, `/categories/new`.
  ///
  /// Currently gated on [Permissions.createProduct]. Introduce a dedicated
  /// category permission if categories need separate access control.
  static const categoryCreate = RouteSpec.child(
    categories,
    'new',
    name: 'categoryNew',
    title: 'New category',
    guard: PermissionGuard({Permissions.createProduct}),
    transition: TransitionPreset.slideFromBottom,
    fullscreen: true,
  );

  /// A single category, `/categories/:categoryId`.
  static const categoryDetail = RouteSpec.child(
    categories,
    ':$categoryId',
    name: 'categoryDetail',
    title: 'Category',
    transition: TransitionPreset.slideFromRight,
  );

  /// The edit form for a category, `/categories/:categoryId/edit`.
  ///
  /// Currently gated on [Permissions.updateProduct], see [categoryCreate].
  static const categoryEdit = RouteSpec.child(
    categoryDetail,
    'edit',
    name: 'categoryEdit',
    title: 'Edit category',
    guard: PermissionGuard({Permissions.updateProduct}),
    transition: TransitionPreset.slideFromBottom,
    fullscreen: true,
  );

  /// Every route this module owns, for the route registry.
  ///
  /// A spec missing here is invisible to guards, titles and analytics, so keep
  /// it in sync with [routes].
  @override
  List<RouteSpec> get specs => const [
    list,
    create,
    detail,
    edit,
    categories,
    categoryCreate,
    categoryDetail,
    categoryEdit,
  ];

  /// Builds the go_router tree for this module.
  ///
  /// [rootNavigatorKey] is used by the full-screen routes ([create],
  /// [categoryCreate], [categoryEdit]) so they render above the shell chrome.
  @override
  List<RouteBase> routes(GlobalKey<NavigatorState> rootNavigatorKey) => [
    list.route(
      builder: (context, state) => const FeaturePlaceholder(title: 'Products Screen'),
      routes: [
        // `new` BEFORE `:productId` - order decides which one wins.
        create.route(
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) =>
              const FeaturePlaceholder(title: 'New product', subtitle: 'Wire AddProductScreen here.'),
        ),
        detail.route(
          // TODO: ProductDetailScreen(productId: state.requireParam(productId))
          builder: (context, state) => const FeaturePlaceholder(title: 'Product details screen'),
          routes: [
            edit.route(
              builder: (context, state) =>
                  FeaturePlaceholder(title: 'Edit product', subtitle: 'Product ${state.requireParam(productId)}'),
            ),
          ],
        ),
      ],
    ),
    categories.route(
      builder: (context, state) => const FeaturePlaceholder(title: 'Category Screen'),
      routes: [
        // `new` BEFORE `:categoryId`, for the same reason as products.
        categoryCreate.route(
          parentNavigatorKey: rootNavigatorKey,
          builder: (context, state) => const FeaturePlaceholder(title: 'Category Form Screen'),
        ),
        categoryDetail.route(
          // TODO: CategoryDetailsScreen(categoryId: state.requireParam(categoryId))
          builder: (context, state) => const FeaturePlaceholder(title: 'Category Details Screen'),
          routes: [
            categoryEdit.route(
              parentNavigatorKey: rootNavigatorKey,
              builder: (context, state) => const FeaturePlaceholder(title: 'Category Form Screen'),
            ),
          ],
        ),
      ],
    ),
  ];
}
