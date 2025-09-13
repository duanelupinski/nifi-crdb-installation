#!/bin/bash

sudo kill -s SIGHUP $(ps aux | grep /[p]rometheus | tr -s " " | cut -f2 -d' ')
