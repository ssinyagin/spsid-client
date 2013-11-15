#  Copyright (C) 2013  Stanislav Sinyagin
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307, USA.

#

SUBST = @abs_top_builddir@/setup_tools/substvars.sh

bin_SCRIPTS = \
	spsid_delete_object \
	spsid_recalc \
	spsid_search \
	spsid_siam_dump_yaml \
	spsid_siam_init \
	spsid_siam_load_yaml

CLEANFILES = $(bin_SCRIPTS)

EXTRA_DIST = \
	spsid_delete_object.in \
	spsid_recalc.in \
	spsid_search.in \
	spsid_siam_dump_yaml.in \
	spsid_siam_init.in \
	spsid_siam_load_yaml.in


spsid_delete_object: spsid_delete_object.in
	$(SUBST) spsid_delete_object.in > spsid_delete_object

spsid_recalc: spsid_recalc.in
	$(SUBST) spsid_recalc.in > spsid_recalc

spsid_search: spsid_search.in
	$(SUBST) spsid_search.in > spsid_search

spsid_siam_dump_yaml: spsid_siam_dump_yaml.in
	$(SUBST) spsid_siam_dump_yaml.in > spsid_siam_dump_yaml

spsid_siam_init: spsid_siam_init.in
	$(SUBST) spsid_siam_init.in > spsid_siam_init

spsid_siam_load_yaml: spsid_siam_load_yaml.in
	$(SUBST) spsid_siam_load_yaml.in > spsid_siam_load_yaml
