extends RefCounted
## TV news crews (NewsCrews, NewsVan, NewsCrew, NewsKit) for tests/smoke_test.gd. Work in progress.


func run(t: Node, city: Node3D) -> void:
	t._check(city.get_node_or_null("NewsCrews") != null, "the city has a NewsCrews node")
