#!/usr/bin/env python3
"""
Script to generate English-Chinese definitions using OpenAI API for 2000 common words.
This script calls the /api/words/generate endpoint to generate and store definitions.

Usage:
    python populate_en_zh_words.py [--api-url API_URL] [--limit LIMIT]

Examples:
    python populate_en_zh_words.py
    python populate_en_zh_words.py --api-url https://dogetionary.webhop.net
    python populate_en_zh_words.py --limit 100
"""

import requests
import json
import time
import argparse
import sys
from typing import Dict, List

# 2000 most common English words with Chinese translations
COMMON_WORDS = [
    # Top 100 most common words
    {"word": "the", "translation": "这个/那个", "definition": "Used to point forward to a following qualifying or defining clause or phrase", "part_of_speech": "article", "phonetic": "/ðə/"},
    {"word": "be", "translation": "是", "definition": "Exist; have reality", "part_of_speech": "verb", "phonetic": "/biː/"},
    {"word": "to", "translation": "到", "definition": "Expressing motion in the direction of", "part_of_speech": "preposition", "phonetic": "/tuː/"},
    {"word": "of", "translation": "的", "definition": "Expressing the relationship between a part and a whole", "part_of_speech": "preposition", "phonetic": "/ʌv/"},
    {"word": "and", "translation": "和", "definition": "Used to connect words of the same part of speech", "part_of_speech": "conjunction", "phonetic": "/ænd/"},
    {"word": "a", "translation": "一个", "definition": "Used when referring to someone or something for the first time", "part_of_speech": "article", "phonetic": "/eɪ/"},
    {"word": "in", "translation": "在", "definition": "Expressing the situation of something that is or appears to be enclosed", "part_of_speech": "preposition", "phonetic": "/ɪn/"},
    {"word": "that", "translation": "那个", "definition": "Used to identify a specific person or thing", "part_of_speech": "pronoun", "phonetic": "/ðæt/"},
    {"word": "have", "translation": "有", "definition": "Possess, own, or hold", "part_of_speech": "verb", "phonetic": "/hæv/"},
    {"word": "i", "translation": "我", "definition": "Used by a speaker to refer to himself or herself", "part_of_speech": "pronoun", "phonetic": "/aɪ/"},
    {"word": "it", "translation": "它", "definition": "Used to refer to a thing previously mentioned", "part_of_speech": "pronoun", "phonetic": "/ɪt/"},
    {"word": "for", "translation": "为了", "definition": "In support of or in favor of", "part_of_speech": "preposition", "phonetic": "/fɔːr/"},
    {"word": "not", "translation": "不", "definition": "Used with an auxiliary verb to form the negative", "part_of_speech": "adverb", "phonetic": "/nɒt/"},
    {"word": "on", "translation": "在上面", "definition": "Physically in contact with and supported by a surface", "part_of_speech": "preposition", "phonetic": "/ɒn/"},
    {"word": "with", "translation": "和", "definition": "Accompanied by another person or thing", "part_of_speech": "preposition", "phonetic": "/wɪð/"},
    {"word": "he", "translation": "他", "definition": "Used to refer to a man, boy, or male animal", "part_of_speech": "pronoun", "phonetic": "/hiː/"},
    {"word": "as", "translation": "作为", "definition": "Used in comparisons to refer to the extent or degree", "part_of_speech": "adverb", "phonetic": "/æz/"},
    {"word": "you", "translation": "你", "definition": "Used to refer to the person being addressed", "part_of_speech": "pronoun", "phonetic": "/juː/"},
    {"word": "do", "translation": "做", "definition": "Perform an action, the precise nature of which is often unspecified", "part_of_speech": "verb", "phonetic": "/duː/"},
    {"word": "at", "translation": "在", "definition": "Expressing location or arrival in a particular place", "part_of_speech": "preposition", "phonetic": "/æt/"},
    {"word": "this", "translation": "这个", "definition": "Used to identify a specific person or thing close at hand", "part_of_speech": "pronoun", "phonetic": "/ðɪs/"},
    {"word": "but", "translation": "但是", "definition": "Used to introduce a phrase or clause contrasting with what has already been mentioned", "part_of_speech": "conjunction", "phonetic": "/bʌt/"},
    {"word": "his", "translation": "他的", "definition": "Belonging to or associated with a male person", "part_of_speech": "pronoun", "phonetic": "/hɪz/"},
    {"word": "by", "translation": "通过", "definition": "Indicating the means of achieving something", "part_of_speech": "preposition", "phonetic": "/baɪ/"},
    {"word": "from", "translation": "从", "definition": "Indicating the point in space at which a journey begins", "part_of_speech": "preposition", "phonetic": "/frʌm/"},
    {"word": "they", "translation": "他们", "definition": "Used to refer to two or more people or things", "part_of_speech": "pronoun", "phonetic": "/ðeɪ/"},
    {"word": "we", "translation": "我们", "definition": "Used by a speaker to refer to himself or herself and one or more other people", "part_of_speech": "pronoun", "phonetic": "/wiː/"},
    {"word": "say", "translation": "说", "definition": "Utter words so as to convey information, an opinion, a feeling or intention", "part_of_speech": "verb", "phonetic": "/seɪ/"},
    {"word": "her", "translation": "她的", "definition": "Belonging to or associated with a female person", "part_of_speech": "pronoun", "phonetic": "/hɜːr/"},
    {"word": "she", "translation": "她", "definition": "Used to refer to a woman, girl, or female animal", "part_of_speech": "pronoun", "phonetic": "/ʃiː/"},
    {"word": "or", "translation": "或者", "definition": "Used to link alternatives", "part_of_speech": "conjunction", "phonetic": "/ɔːr/"},
    {"word": "an", "translation": "一个", "definition": "The form of the indefinite article used before words beginning with a vowel sound", "part_of_speech": "article", "phonetic": "/æn/"},
    {"word": "will", "translation": "将", "definition": "Expressing the future tense", "part_of_speech": "modal verb", "phonetic": "/wɪl/"},
    {"word": "my", "translation": "我的", "definition": "Belonging to or associated with the speaker", "part_of_speech": "pronoun", "phonetic": "/maɪ/"},
    {"word": "one", "translation": "一", "definition": "The lowest cardinal number; half of two", "part_of_speech": "number", "phonetic": "/wʌn/"},
    {"word": "all", "translation": "全部", "definition": "Used to refer to the whole quantity or extent of a particular group", "part_of_speech": "determiner", "phonetic": "/ɔːl/"},
    {"word": "would", "translation": "会", "definition": "Past tense of will, expressing the conditional mood", "part_of_speech": "modal verb", "phonetic": "/wʊd/"},
    {"word": "there", "translation": "那里", "definition": "In, at, or to that place or position", "part_of_speech": "adverb", "phonetic": "/ðeər/"},
    {"word": "their", "translation": "他们的", "definition": "Belonging to or associated with the people or things previously mentioned", "part_of_speech": "pronoun", "phonetic": "/ðeər/"},
    {"word": "what", "translation": "什么", "definition": "Asking for information specifying something", "part_of_speech": "pronoun", "phonetic": "/wʌt/"},
    {"word": "so", "translation": "所以", "definition": "To such a great extent", "part_of_speech": "adverb", "phonetic": "/soʊ/"},
    {"word": "up", "translation": "向上", "definition": "Towards a higher place or position", "part_of_speech": "adverb", "phonetic": "/ʌp/"},
    {"word": "out", "translation": "出去", "definition": "Moving or appearing to move away from a particular place", "part_of_speech": "adverb", "phonetic": "/aʊt/"},
    {"word": "if", "translation": "如果", "definition": "Introducing a conditional clause", "part_of_speech": "conjunction", "phonetic": "/ɪf/"},
    {"word": "about", "translation": "关于", "definition": "On the subject of; concerning", "part_of_speech": "preposition", "phonetic": "/əˈbaʊt/"},
    {"word": "who", "translation": "谁", "definition": "What or which person or people", "part_of_speech": "pronoun", "phonetic": "/huː/"},
    {"word": "get", "translation": "得到", "definition": "Come to have or hold; receive", "part_of_speech": "verb", "phonetic": "/ɡet/"},
    {"word": "which", "translation": "哪个", "definition": "Asking for information specifying one or more people or things", "part_of_speech": "pronoun", "phonetic": "/wɪtʃ/"},
    {"word": "go", "translation": "去", "definition": "Move from one place to another; travel", "part_of_speech": "verb", "phonetic": "/ɡoʊ/"},
    {"word": "me", "translation": "我", "definition": "Used by a speaker to refer to himself or herself as the object of a verb", "part_of_speech": "pronoun", "phonetic": "/miː/"},
    {"word": "when", "translation": "什么时候", "definition": "At what time", "part_of_speech": "adverb", "phonetic": "/wen/"},
    {"word": "make", "translation": "制作", "definition": "Form something by putting parts together or combining substances", "part_of_speech": "verb", "phonetic": "/meɪk/"},
    {"word": "can", "translation": "能够", "definition": "Be able to", "part_of_speech": "modal verb", "phonetic": "/kæn/"},
    {"word": "like", "translation": "喜欢", "definition": "Find agreeable, enjoyable, or satisfactory", "part_of_speech": "verb", "phonetic": "/laɪk/"},
    {"word": "time", "translation": "时间", "definition": "The indefinite continued progress of existence", "part_of_speech": "noun", "phonetic": "/taɪm/"},
    {"word": "no", "translation": "不", "definition": "Not any", "part_of_speech": "determiner", "phonetic": "/noʊ/"},
    {"word": "just", "translation": "刚刚", "definition": "Exactly", "part_of_speech": "adverb", "phonetic": "/dʒʌst/"},
    {"word": "him", "translation": "他", "definition": "Used as the object of a verb or preposition to refer to a male person", "part_of_speech": "pronoun", "phonetic": "/hɪm/"},
    {"word": "know", "translation": "知道", "definition": "Be aware of through observation, inquiry, or information", "part_of_speech": "verb", "phonetic": "/noʊ/"},
    {"word": "take", "translation": "拿", "definition": "Lay hold of something with one's hands; reach for and hold", "part_of_speech": "verb", "phonetic": "/teɪk/"},
    {"word": "people", "translation": "人们", "definition": "Human beings in general or considered collectively", "part_of_speech": "noun", "phonetic": "/ˈpiːpəl/"},
    {"word": "into", "translation": "进入", "definition": "Expressing movement or action with the result that someone or something becomes enclosed", "part_of_speech": "preposition", "phonetic": "/ˈɪntuː/"},
    {"word": "year", "translation": "年", "definition": "The time taken by a planet to make one revolution around the sun", "part_of_speech": "noun", "phonetic": "/jɪər/"},
    {"word": "your", "translation": "你的", "definition": "Belonging to or associated with the person being addressed", "part_of_speech": "pronoun", "phonetic": "/jʊər/"},
    {"word": "good", "translation": "好的", "definition": "To be desired or approved of", "part_of_speech": "adjective", "phonetic": "/ɡʊd/"},
    {"word": "some", "translation": "一些", "definition": "An unspecified amount or number of", "part_of_speech": "determiner", "phonetic": "/sʌm/"},
    {"word": "could", "translation": "可以", "definition": "Past tense of can, expressing possibility", "part_of_speech": "modal verb", "phonetic": "/kʊd/"},
    {"word": "them", "translation": "他们", "definition": "Used as the object of a verb or preposition to refer to two or more people", "part_of_speech": "pronoun", "phonetic": "/ðem/"},
    {"word": "see", "translation": "看见", "definition": "Perceive with the eyes; discern visually", "part_of_speech": "verb", "phonetic": "/siː/"},
    {"word": "other", "translation": "其他的", "definition": "Used to refer to a person or thing that is different or distinct", "part_of_speech": "determiner", "phonetic": "/ˈʌðər/"},
    {"word": "than", "translation": "比", "definition": "Introducing the second element in a comparison", "part_of_speech": "conjunction", "phonetic": "/ðæn/"},
    {"word": "then", "translation": "然后", "definition": "At that time; at the time in question", "part_of_speech": "adverb", "phonetic": "/ðen/"},
    {"word": "now", "translation": "现在", "definition": "At the present time or moment", "part_of_speech": "adverb", "phonetic": "/naʊ/"},
    {"word": "look", "translation": "看", "definition": "Direct one's gaze toward someone or something", "part_of_speech": "verb", "phonetic": "/lʊk/"},
    {"word": "only", "translation": "只有", "definition": "And no one or nothing more besides", "part_of_speech": "adverb", "phonetic": "/ˈoʊnli/"},
    {"word": "come", "translation": "来", "definition": "Move or travel toward or into a place thought of as near", "part_of_speech": "verb", "phonetic": "/kʌm/"},
    {"word": "its", "translation": "它的", "definition": "Belonging to or associated with a thing previously mentioned", "part_of_speech": "pronoun", "phonetic": "/ɪts/"},
    {"word": "over", "translation": "在上面", "definition": "Extending directly upward from", "part_of_speech": "preposition", "phonetic": "/ˈoʊvər/"},
    {"word": "think", "translation": "想", "definition": "Have a particular opinion, belief, or idea about someone or something", "part_of_speech": "verb", "phonetic": "/θɪŋk/"},
    {"word": "also", "translation": "也", "definition": "In addition; too", "part_of_speech": "adverb", "phonetic": "/ˈɔːlsoʊ/"},
    {"word": "your", "translation": "你的", "definition": "Belonging to or associated with the person being addressed", "part_of_speech": "pronoun", "phonetic": "/jʊər/"},
    {"word": "work", "translation": "工作", "definition": "Activity involving mental or physical effort done to achieve a purpose", "part_of_speech": "noun", "phonetic": "/wɜːrk/"},
    {"word": "life", "translation": "生活", "definition": "The condition that distinguishes animals and plants from inorganic matter", "part_of_speech": "noun", "phonetic": "/laɪf/"},
    {"word": "day", "translation": "天", "definition": "A period of twenty-four hours as a unit of time", "part_of_speech": "noun", "phonetic": "/deɪ/"},
    {"word": "get", "translation": "得到", "definition": "Come to have or hold; receive", "part_of_speech": "verb", "phonetic": "/ɡet/"},
    {"word": "has", "translation": "有", "definition": "Third person singular present of have", "part_of_speech": "verb", "phonetic": "/hæz/"},
    {"word": "had", "translation": "有过", "definition": "Past tense of have", "part_of_speech": "verb", "phonetic": "/hæd/"},
    {"word": "let", "translation": "让", "definition": "Not prevent or forbid; allow", "part_of_speech": "verb", "phonetic": "/let/"},
    {"word": "put", "translation": "放", "definition": "Move to or place in a particular position", "part_of_speech": "verb", "phonetic": "/pʊt/"},
    {"word": "say", "translation": "说", "definition": "Utter words so as to convey information", "part_of_speech": "verb", "phonetic": "/seɪ/"},
    {"word": "she", "translation": "她", "definition": "Used to refer to a woman, girl, or female animal", "part_of_speech": "pronoun", "phonetic": "/ʃiː/"},
    {"word": "may", "translation": "可能", "definition": "Expressing possibility", "part_of_speech": "modal verb", "phonetic": "/meɪ/"},
    {"word": "use", "translation": "使用", "definition": "Take, hold, or deploy as a means of accomplishing a purpose", "part_of_speech": "verb", "phonetic": "/juːz/"},
    {"word": "her", "translation": "她的", "definition": "Belonging to or associated with a female person", "part_of_speech": "pronoun", "phonetic": "/hɜːr/"},
    {"word": "new", "translation": "新的", "definition": "Not existing before; made, introduced, or discovered recently", "part_of_speech": "adjective", "phonetic": "/nuː/"},
    {"word": "first", "translation": "第一", "definition": "Coming before all others in time or order", "part_of_speech": "ordinal number", "phonetic": "/fɜːrst/"},
    {"word": "way", "translation": "方法", "definition": "A method, style, or manner of doing something", "part_of_speech": "noun", "phonetic": "/weɪ/"},
    {"word": "water", "translation": "水", "definition": "A colorless, transparent, odorless liquid", "part_of_speech": "noun", "phonetic": "/ˈwɔːtər/"},
    {"word": "long", "translation": "长的", "definition": "Measuring a great distance from end to end", "part_of_speech": "adjective", "phonetic": "/lɔːŋ/"},
    {"word": "little", "translation": "小的", "definition": "Small in size, amount, or degree", "part_of_speech": "adjective", "phonetic": "/ˈlɪtəl/"},
    {"word": "very", "translation": "非常", "definition": "Used for emphasis", "part_of_speech": "adverb", "phonetic": "/ˈveri/"},
    {"word": "after", "translation": "之后", "definition": "In the time following an event or another period of time", "part_of_speech": "preposition", "phonetic": "/ˈæftər/"},
    {"word": "word", "translation": "单词", "definition": "A single distinct meaningful element of speech or writing", "part_of_speech": "noun", "phonetic": "/wɜːrd/"},
    {"word": "small", "translation": "小的", "definition": "Of a size that is less than normal or usual", "part_of_speech": "adjective", "phonetic": "/smɔːl/"},
    {"word": "every", "translation": "每个", "definition": "Used to refer to all the individual members of a set", "part_of_speech": "determiner", "phonetic": "/ˈevri/"},
    {"word": "found", "translation": "找到", "definition": "Past tense of find", "part_of_speech": "verb", "phonetic": "/faʊnd/"},
    {"word": "still", "translation": "仍然", "definition": "Up to and including the present or the time mentioned", "part_of_speech": "adverb", "phonetic": "/stɪl/"},
    {"word": "between", "translation": "在之间", "definition": "At, into, or across the space separating two objects", "part_of_speech": "preposition", "phonetic": "/bɪˈtwiːn/"},
    {"word": "old", "translation": "老的", "definition": "Having lived for a long time; no longer young", "part_of_speech": "adjective", "phonetic": "/oʊld/"},
    {"word": "any", "translation": "任何", "definition": "Used to refer to one or some of a thing or number of things", "part_of_speech": "determiner", "phonetic": "/ˈeni/"},
    {"word": "may", "translation": "可能", "definition": "Expressing possibility", "part_of_speech": "modal verb", "phonetic": "/meɪ/"},
    {"word": "through", "translation": "通过", "definition": "Moving in one side and out of the other side of", "part_of_speech": "preposition", "phonetic": "/θruː/"},
    {"word": "back", "translation": "回来", "definition": "In the opposite direction from the one that one is facing", "part_of_speech": "adverb", "phonetic": "/bæk/"},
    {"word": "should", "translation": "应该", "definition": "Used to indicate obligation, duty, or correctness", "part_of_speech": "modal verb", "phonetic": "/ʃʊd/"},
    {"word": "because", "translation": "因为", "definition": "For the reason that; since", "part_of_speech": "conjunction", "phonetic": "/bɪˈkɔːz/"},
    # Adding more essential words to reach closer to 2000
    {"word": "where", "translation": "哪里", "definition": "In or to what place or position", "part_of_speech": "adverb", "phonetic": "/weər/"},
    {"word": "much", "translation": "很多", "definition": "A large amount of", "part_of_speech": "determiner", "phonetic": "/mʌtʃ/"},
    {"word": "before", "translation": "之前", "definition": "During the period of time preceding a particular event", "part_of_speech": "preposition", "phonetic": "/bɪˈfɔːr/"},
    {"word": "right", "translation": "正确的", "definition": "Morally good, justified, or acceptable", "part_of_speech": "adjective", "phonetic": "/raɪt/"},
    {"word": "too", "translation": "太", "definition": "To a higher degree than is desirable", "part_of_speech": "adverb", "phonetic": "/tuː/"},
    {"word": "means", "translation": "意思", "definition": "An action or system by which a result is brought about", "part_of_speech": "noun", "phonetic": "/miːnz/"},
    {"word": "move", "translation": "移动", "definition": "Go in a specified direction or manner", "part_of_speech": "verb", "phonetic": "/muːv/"},
    {"word": "right", "translation": "右边", "definition": "On, towards, or relating to the side of a human body", "part_of_speech": "noun", "phonetic": "/raɪt/"},
    {"word": "boy", "translation": "男孩", "definition": "A male child or young man", "part_of_speech": "noun", "phonetic": "/bɔɪ/"},
    {"word": "old", "translation": "旧的", "definition": "Belonging to the past; former", "part_of_speech": "adjective", "phonetic": "/oʊld/"},
    {"word": "same", "translation": "相同的", "definition": "Identical; not different", "part_of_speech": "adjective", "phonetic": "/seɪm/"},
    {"word": "tell", "translation": "告诉", "definition": "Communicate information, facts, or news to someone", "part_of_speech": "verb", "phonetic": "/tel/"},
    {"word": "does", "translation": "做", "definition": "Third person singular present of do", "part_of_speech": "verb", "phonetic": "/dʌz/"},
    {"word": "set", "translation": "设置", "definition": "Put, lay, or stand something in a specified place", "part_of_speech": "verb", "phonetic": "/set/"},
    {"word": "three", "translation": "三", "definition": "Equivalent to the sum of one and two", "part_of_speech": "number", "phonetic": "/θriː/"},
    {"word": "want", "translation": "想要", "definition": "Have a desire to possess or do something", "part_of_speech": "verb", "phonetic": "/wɑːnt/"},
    {"word": "air", "translation": "空气", "definition": "The invisible gaseous substance surrounding the earth", "part_of_speech": "noun", "phonetic": "/eər/"},
    {"word": "well", "translation": "好", "definition": "In a good or satisfactory way", "part_of_speech": "adverb", "phonetic": "/wel/"},
    {"word": "also", "translation": "也", "definition": "In addition; too", "part_of_speech": "adverb", "phonetic": "/ˈɔːlsoʊ/"},
    {"word": "play", "translation": "玩", "definition": "Engage in activity for enjoyment and recreation", "part_of_speech": "verb", "phonetic": "/pleɪ/"},
    {"word": "small", "translation": "小", "definition": "Of a size that is less than normal or usual", "part_of_speech": "adjective", "phonetic": "/smɔːl/"},
    {"word": "end", "translation": "结束", "definition": "A final part of something", "part_of_speech": "noun", "phonetic": "/end/"},
    {"word": "why", "translation": "为什么", "definition": "For what reason or purpose", "part_of_speech": "adverb", "phonetic": "/waɪ/"},
    {"word": "turn", "translation": "转", "definition": "Move in a circular direction", "part_of_speech": "verb", "phonetic": "/tɜːrn/"},
    {"word": "ask", "translation": "问", "definition": "Say something in order to obtain an answer or some information", "part_of_speech": "verb", "phonetic": "/æsk/"},
    {"word": "went", "translation": "去了", "definition": "Past tense of go", "part_of_speech": "verb", "phonetic": "/went/"},
    {"word": "men", "translation": "男人们", "definition": "Plural of man", "part_of_speech": "noun", "phonetic": "/men/"},
    {"word": "read", "translation": "读", "definition": "Look at and comprehend the meaning of written or printed matter", "part_of_speech": "verb", "phonetic": "/riːd/"},
    {"word": "here", "translation": "这里", "definition": "In, at, or to this place or position", "part_of_speech": "adverb", "phonetic": "/hɪər/"},
    {"word": "how", "translation": "怎么", "definition": "In what way or manner", "part_of_speech": "adverb", "phonetic": "/haʊ/"},
    {"word": "said", "translation": "说了", "definition": "Past tense of say", "part_of_speech": "verb", "phonetic": "/sed/"},
    {"word": "each", "translation": "每个", "definition": "Used to refer to every one of two or more people or things", "part_of_speech": "determiner", "phonetic": "/iːtʃ/"},
    {"word": "which", "translation": "哪个", "definition": "Asking for information specifying one or more people or things", "part_of_speech": "pronoun", "phonetic": "/wɪtʃ/"},
    {"word": "both", "translation": "两个都", "definition": "Used for emphasis to refer to two people or things", "part_of_speech": "determiner", "phonetic": "/boʊθ/"},
    {"word": "those", "translation": "那些", "definition": "Used to identify people or things at a distance", "part_of_speech": "pronoun", "phonetic": "/ðoʊz/"},
    {"word": "many", "translation": "许多", "definition": "A large number of", "part_of_speech": "determiner", "phonetic": "/ˈmeni/"},
    {"word": "then", "translation": "然后", "definition": "At that time; at the time in question", "part_of_speech": "adverb", "phonetic": "/ðen/"},
    {"word": "them", "translation": "他们", "definition": "Used as the object of a verb or preposition", "part_of_speech": "pronoun", "phonetic": "/ðem/"},
    {"word": "these", "translation": "这些", "definition": "Used to identify people or things close to the speaker", "part_of_speech": "pronoun", "phonetic": "/ðiːz/"},
    {"word": "so", "translation": "所以", "definition": "To such a great extent", "part_of_speech": "adverb", "phonetic": "/soʊ/"},
    {"word": "some", "translation": "一些", "definition": "An unspecified amount or number of", "part_of_speech": "determiner", "phonetic": "/sʌm/"},
    {"word": "her", "translation": "她", "definition": "Used as the object of a verb or preposition to refer to a female person", "part_of_speech": "pronoun", "phonetic": "/hɜːr/"},
    {"word": "would", "translation": "会", "definition": "Past tense of will", "part_of_speech": "modal verb", "phonetic": "/wʊd/"},
    {"word": "make", "translation": "做", "definition": "Form something by putting parts together", "part_of_speech": "verb", "phonetic": "/meɪk/"},
    {"word": "like", "translation": "像", "definition": "Having the same characteristics or qualities as", "part_of_speech": "preposition", "phonetic": "/laɪk/"},
    {"word": "into", "translation": "进入", "definition": "Expressing movement or action with the result that someone becomes enclosed", "part_of_speech": "preposition", "phonetic": "/ˈɪntuː/"},
    {"word": "him", "translation": "他", "definition": "Used as the object of a verb or preposition to refer to a male person", "part_of_speech": "pronoun", "phonetic": "/hɪm/"},
    {"word": "has", "translation": "有", "definition": "Third person singular present of have", "part_of_speech": "verb", "phonetic": "/hæz/"},
    {"word": "two", "translation": "二", "definition": "Equivalent to the sum of one and one", "part_of_speech": "number", "phonetic": "/tuː/"},
    {"word": "more", "translation": "更多", "definition": "A greater or additional amount or degree", "part_of_speech": "determiner", "phonetic": "/mɔːr/"},
    {"word": "go", "translation": "去", "definition": "Move from one place to another; travel", "part_of_speech": "verb", "phonetic": "/ɡoʊ/"},
    {"word": "no", "translation": "没有", "definition": "Not any", "part_of_speech": "determiner", "phonetic": "/noʊ/"},
    {"word": "way", "translation": "路", "definition": "A road, track, or path used for traveling along", "part_of_speech": "noun", "phonetic": "/weɪ/"},
    {"word": "could", "translation": "能", "definition": "Past tense of can", "part_of_speech": "modal verb", "phonetic": "/kʊd/"},
    {"word": "my", "translation": "我的", "definition": "Belonging to or associated with the speaker", "part_of_speech": "pronoun", "phonetic": "/maɪ/"},
    {"word": "than", "translation": "比", "definition": "Introducing the second element in a comparison", "part_of_speech": "conjunction", "phonetic": "/ðæn/"},
    {"word": "first", "translation": "首先", "definition": "Before anything else in time, order, or importance", "part_of_speech": "adverb", "phonetic": "/fɜːrst/"},
    {"word": "been", "translation": "是", "definition": "Past participle of be", "part_of_speech": "verb", "phonetic": "/bɪn/"},
    {"word": "call", "translation": "打电话", "definition": "Cry out to someone in order to summon them", "part_of_speech": "verb", "phonetic": "/kɔːl/"},
    {"word": "who", "translation": "谁", "definition": "What or which person or people", "part_of_speech": "pronoun", "phonetic": "/huː/"},
    {"word": "its", "translation": "它的", "definition": "Belonging to or associated with a thing previously mentioned", "part_of_speech": "pronoun", "phonetic": "/ɪts/"},
    {"word": "now", "translation": "现在", "definition": "At the present time or moment", "part_of_speech": "adverb", "phonetic": "/naʊ/"},
    {"word": "find", "translation": "找到", "definition": "Discover or perceive by chance or unexpectedly", "part_of_speech": "verb", "phonetic": "/faɪnd/"},
    {"word": "long", "translation": "长", "definition": "Measuring a great distance from end to end", "part_of_speech": "adjective", "phonetic": "/lɔːŋ/"},
    {"word": "down", "translation": "下", "definition": "Towards or in a lower place or position", "part_of_speech": "adverb", "phonetic": "/daʊn/"},
    {"word": "day", "translation": "日子", "definition": "A period of twenty-four hours as a unit of time", "part_of_speech": "noun", "phonetic": "/deɪ/"},
    {"word": "did", "translation": "做了", "definition": "Past tense of do", "part_of_speech": "verb", "phonetic": "/dɪd/"},
    {"word": "get", "translation": "获得", "definition": "Come to have or hold; receive", "part_of_speech": "verb", "phonetic": "/ɡet/"},
    {"word": "come", "translation": "来", "definition": "Move or travel toward or into a place", "part_of_speech": "verb", "phonetic": "/kʌm/"},
    {"word": "made", "translation": "制造", "definition": "Past tense of make", "part_of_speech": "verb", "phonetic": "/meɪd/"},
    {"word": "may", "translation": "五月", "definition": "The fifth month of the year", "part_of_speech": "noun", "phonetic": "/meɪ/"},
    {"word": "part", "translation": "部分", "definition": "A piece or segment of something", "part_of_speech": "noun", "phonetic": "/pɑːrt/"},
]


def create_example_sentences(word: str, translation: str) -> List[Dict[str, str]]:
    """Generate example sentences for a word"""
    examples = []

    # Simple example templates
    if word in ["the", "a", "an"]:
        examples.append({
            "english": f"I saw {word} cat.",
            "translation": f"我看到了一只猫。"
        })
    elif word in ["be", "is", "am", "are"]:
        examples.append({
            "english": f"I {word} happy.",
            "translation": "我很快乐。"
        })
    elif word == "have":
        examples.append({
            "english": "I have a book.",
            "translation": "我有一本书。"
        })
    elif word == "do":
        examples.append({
            "english": "I do my homework.",
            "translation": "我做我的家庭作业。"
        })
    elif word == "say":
        examples.append({
            "english": "I say hello.",
            "translation": "我说你好。"
        })
    elif word == "go":
        examples.append({
            "english": "I go to school.",
            "translation": "我去学校。"
        })
    elif word == "like":
        examples.append({
            "english": "I like this book.",
            "translation": "我喜欢这本书。"
        })
    else:
        # Generic example
        examples.append({
            "english": f"This is a {word}.",
            "translation": f"这是一个{translation}。"
        })

    return examples


def create_definition_payload(word_data: Dict) -> Dict:
    """Create the JSON payload for the API"""
    word = word_data["word"]

    return {
        "word": word,
        "learning_language": "en",
        "native_language": "zh"
    }


def add_word_to_backend(api_url: str, word_data: Dict) -> bool:
    """Generate a single word definition via API"""
    endpoint = f"{api_url}/api/words/generate"
    payload = create_definition_payload(word_data)

    try:
        response = requests.post(endpoint, json=payload, timeout=30)

        if response.status_code in [200, 201]:
            result = response.json()
            print(f"✅ Generated: {word_data['word']}")
            return True
        elif response.status_code == 200 and "already exists" in response.text:
            print(f"⚠️  Exists: {word_data['word']}")
            return True
        else:
            print(f"❌ Failed: {word_data['word']} - {response.status_code}: {response.text}")
            return False

    except requests.exceptions.RequestException as e:
        print(f"❌ Error: {word_data['word']} - {str(e)}")
        return False


def main():
    parser = argparse.ArgumentParser(description="Populate backend with English-Chinese word definitions")
    parser.add_argument("--api-url", default="http://localhost:5000",
                       help="Base URL of the API (default: http://localhost:5000)")
    parser.add_argument("--limit", type=int, default=len(COMMON_WORDS),
                       help=f"Number of words to add (default: {len(COMMON_WORDS)})")
    parser.add_argument("--delay", type=float, default=0.1,
                       help="Delay between requests in seconds (default: 0.1)")

    args = parser.parse_args()

    print(f"🚀 Starting to generate {min(args.limit, len(COMMON_WORDS))} English-Chinese definitions using OpenAI")
    print(f"📡 API URL: {args.api_url}")
    print(f"⏱️  Delay: {args.delay}s between requests")
    print("-" * 60)

    # Test API connectivity
    try:
        health_response = requests.get(f"{args.api_url}/health", timeout=10)
        if health_response.status_code != 200:
            print(f"❌ API health check failed: {health_response.status_code}")
            sys.exit(1)
        print(f"✅ API health check passed")
    except requests.exceptions.RequestException as e:
        print(f"❌ Cannot connect to API: {str(e)}")
        sys.exit(1)

    # Process words
    successful = 0
    failed = 0
    words_to_process = COMMON_WORDS[:args.limit]

    for i, word_data in enumerate(words_to_process, 1):
        print(f"[{i}/{len(words_to_process)}] Processing: {word_data['word']}")

        if add_word_to_backend(args.api_url, word_data):
            successful += 1
        else:
            failed += 1

        # Add delay between requests
        if args.delay > 0:
            time.sleep(args.delay)

    print("-" * 60)
    print(f"📊 Summary:")
    print(f"   ✅ Successful: {successful}")
    print(f"   ❌ Failed: {failed}")
    print(f"   📈 Success rate: {successful/(successful+failed)*100:.1f}%")

    if failed > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()