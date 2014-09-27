# mission dumper mod
#
# based in part on work done by Phalynx and Locastan 
# based in part on the xvmstat mod
#
# based largely on too much caffeine

__author__ = 'Scrambled'
import os
import cPickle
from debug_utils import *
from PlayerEvents import g_playerEvents
from gui.shared import g_eventsCache
from gui.shared.server_events.event_items import Quest, Action
from json import dumps, loads, JSONEncoder, JSONDecoder
from threading import Thread
from urlparse import urlparse
import httplib
import constants
import traceback

class StatterboxEncoder(JSONEncoder):
    def default(self, obj):
        if isinstance(obj, (list, dict, str, unicode, int, float, bool, type(None))):
            return JSONEncoder.default(self, obj)
        elif isinstance(obj, set):
            return list(obj)
        return {'pickle': cPickle.dumps(obj)}

class StatterboxMissionSubmitter(object):
    def __init__(self, jsonString): 
        self.jsonString = jsonString
    
    def submit(self): 
        u = urlparse('http://api.statterbox.com/util/mission/submit')
        print('[Statterbox.submit] to ' + repr(u))
        try:
            conn = httplib.HTTPConnection(u.netloc, timeout=5)
            conn.request('POST', u.path, self.jsonString, { "Content-Type": "application/json" })
            response = conn.getresponse()
            print(response.status, response.reason)
            print(response.read())
        except Exception as e:
            traceback.format_exc()
            LOG_CURRENT_EXCEPTION()

class StatterboxMissionDumper(object): 
    @staticmethod
    def dumpQuests():
        try:
            quests = g_eventsCache.getQuests()

            print('[Statterbox.dumpQuests]: dumping quests');

            # quests is a dict of quest names with quest objects, 
            # the quest objects individually don't serialize to JSON very well
            # so we want to reconstruct a few things there

            jsonQuests = {}

            for questName, quest in quests.items():
                bonuses = {}
                conditions = {}
                modifiers = {}
                childList = []
                parentList = []
                bonus_limit = None
                process = False

                # oy vey
                if isinstance(quest, Quest):
                    for n, v in quest._data.get('bonus', {}).iteritems():
                        if(isinstance(v, dict)):
                            res = list()
                            for typeid, typecount in v.items():
                                res.append({ "item": typeid, "count": typecount})
                            bonuses[n] = res
                        else:
                            bonuses[n] = v;
                    
                    conditionRaw = quest._data.get('conditions', {})
                    if(isinstance(conditionRaw, dict)):
                        for n, v in conditionRaw.iteritems():
                            name = '%s' % n
                            conditions[name] = v;


                    for child in quest.getChildren():
                        childList.append(child)
                    
                    for parent in quest.getParents():
                        parentList.append(parent)

                    process = True

                if process == True:
                    questDesc = ''
                    questName = 'Unknown'

                    try:
                        nameLocales = quest._data.get('name', {});
                        questName   = nameLocales[constants.DEFAULT_LANGUAGE]
                    except Exception:
                        questName = 'Unknown (Exception)'

                    try:
                        descLocales = quest._data.get('description', {});
                        questDesc   = descLocales[constants.DEFAULT_LANGUAGE]
                    except Exception:
                        questDesc = ''

                    jsonQuests[questName] = {
                        "stb_version"       :   3,
                        "wot_version"       :   "0.9.3",
                        "wot_version_n"     :   90300,
                        "type"              :   quest.getType(),
                        "id"                :   quest.getID(),
                        "start_time"        :   quest.getStartTime(),
                        "finish_time"       :   quest.getFinishTime(),
                        "creation_time"     :   quest.getCreationTime(),
                        "destroying_time"   :   quest.getDestroyingTime(),
                        "name"              :   questName,
                        "description"       :   questDesc,
                        "is_igr"            :   quest.isIGR(),
                        "user_type"         :   quest.getUserType(),
                        "children"          :   childList,
                        "parents"           :   parentList,
                        "bonuses"           :   bonuses,
                        "conditions"        :   conditions,
                        "modifiers"         :   modifiers,
                    }

            jsonString = dumps({
                "version": 3,
                "missions": jsonQuests,
            }, cls=StatterboxEncoder);
            submit = StatterboxMissionSubmitter(jsonString);

            thread = Thread(target=submit.submit);
            thread.start()

        except Exception as e:
            LOG_CURRENT_EXCEPTION()
        finally:
            # because we only want to do this once per game run 
            g_eventsCache.onSyncCompleted -= StatterboxMissionDumper.dumpQuests

# started when the whole enchilada is loaded
g_eventsCache.onSyncCompleted += StatterboxMissionDumper.dumpQuests
print('[Statterbox] Mission dumper loaded');
