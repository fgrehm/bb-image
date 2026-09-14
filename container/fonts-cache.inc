<!--
	The one and only cache directory. Naming it explicitly matters: a config with
	no <cachedir> at all makes fontconfig re-add /var/cache/fontconfig from its
	compiled-in defaults, and warn about having done so.
-->
	<cachedir prefix="xdg">fontconfig</cachedir>

