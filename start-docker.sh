#!/bin/bash

sudo docker run -t -i -p 2020:2020 -v ~/dev/the-resistance/:/home/game/ steve/mongo-nodejs /bin/bash
