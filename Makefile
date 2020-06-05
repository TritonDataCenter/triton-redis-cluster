# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

# Copyright 2020 Joyent, Inc.

node_modules: package.json
	npm install

clean:
	rm -rf node_modules package-lock.json
