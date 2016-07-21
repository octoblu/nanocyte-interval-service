_          = require 'lodash'
async      = require 'async'
debug      = require('debug')('nanocyte-interval-service:register-job-processor')
cronParser = require 'cron-parser'
Redlock    = require 'redlock'

class RegisterJobProcessor
  constructor: (options) ->
    {@client,@kue,@queue,@pingInterval,@intervalAttempts,@intervalTTL,@minTimeDiff} = options
    @redlock = new Redlock [@client], retryCount: 20, retryDelay: 100

  processJob: (job, ignore, callback) =>
    debug 'processing register job', job.id, 'data', JSON.stringify job.data
    {nodeId, sendTo} = job.data
    key = "#{sendTo}/#{nodeId}"
    @redlock.lock key, 5000, (error, lock) =>
      return callback error if error?

      async.series [
        async.apply @doUnregister, job.data
        async.apply @removeDisabledKey, job.data
        async.apply @createIntervalProperties, job.data
        async.apply @createPingJob, job.data
        async.apply @createIntervalJob, job.data
      ], (error) =>
        lock.unlock()
        callback error

  createPingJob: (data, callback) =>
    {sendTo, nodeId, fireOnce} = data
    return callback() if fireOnce
    job = @queue.create('ping', data)
      .ttl(5000)
      .events(false)
      .delay(@pingInterval)
      .removeOnComplete(true)
      .save (error) =>
        return callback error if error?
        @client.set "interval/ping/#{sendTo}/#{nodeId}", job.id, callback

  updateCronIntervalTime: ({cronString, sendTo, nodeId}, callback) =>
    return callback() if _.isEmpty cronString
    try
      intervalTime = @calculateNextCronInterval cronString
    catch error
      console.error 'calculateNextCronInterval', error
      return callback() if error?

    @client.set "interval/time/#{sendTo}/#{nodeId}", intervalTime, (error) =>
      return callback error if error?
      callback null, intervalTime

  createIntervalJob: (data, callback) =>
    {cronString, sendTo, nodeId, intervalTime} = data
    @updateCronIntervalTime {cronString, sendTo, nodeId}, (error, cronIntervalTime) =>
      return callback error if error?
      intervalTime = cronIntervalTime if cronIntervalTime?
      data.intervalTime = intervalTime
      if intervalTime < @minTimeDiff
        console.error new Error "invalid intervalTime: #{intervalTime}"
        console.error {data}
        return callback()

      job = @queue.create('interval', data)
        .events(false)
        .delay(intervalTime)
        .removeOnComplete(true)
        .attempts(@intervalAttempts)
        .ttl(@intervalTTL)
        .save (error) =>
          return callback error if error?
          async.series [
            async.apply @client.del, "interval/job/#{sendTo}/#{nodeId}"
            async.apply @client.sadd, "interval/job/#{sendTo}/#{nodeId}", job.id
          ], callback

  createIntervalProperties: (data, callback) =>
    {sendTo, nodeId, intervalTime, cronString, nonce} = data
    @client.mset "interval/active/#{sendTo}/#{nodeId}", 'true',
      "interval/origTime/#{sendTo}/#{nodeId}", intervalTime || '',
      "interval/time/#{sendTo}/#{nodeId}", intervalTime || '',
      "interval/cron/#{sendTo}/#{nodeId}", cronString || '',
      "interval/nonce/#{sendTo}/#{nodeId}", nonce || ''
    , callback

  calculateNextCronInterval: (cronString, currentDate) =>
    currentDate ?= new Date
    timeDiff = 0
    parser = cronParser.parseExpression cronString, currentDate: currentDate
    while timeDiff <= @minTimeDiff
      nextDate = parser.next()?.toDate()
      if nextDate?
        nextDate.setMilliseconds 0
        timeDiff = nextDate - currentDate

    return timeDiff

  removeDisabledKey: ({sendTo,nodeId}, callback) =>
    @client.hdel 'ping:disabled', "#{sendTo}:#{nodeId}", callback

  doUnregister: ({sendTo, nodeId}, callback) =>
    async.series [
      async.apply @removeIntervalProperties, {sendTo, nodeId}
      async.apply @removeIntervalJobs, {sendTo, nodeId}
      async.apply @removePingJob, {sendTo, nodeId}
    ], callback

  removeIntervalProperties: ({sendTo, nodeId}, callback) =>
      @client.del "interval/active/#{sendTo}/#{nodeId}",
      "interval/time/#{sendTo}/#{nodeId}",
      "interval/cron/#{sendTo}/#{nodeId}",
      "interval/nonce/#{sendTo}/#{nodeId}", callback

  removeIntervalJobs: ({sendTo, nodeId}, callback) =>
    @client.smembers "interval/job/#{sendTo}/#{nodeId}", (error, jobIds) =>
      return callback error if error?
      async.each jobIds, @removeJob, callback

  removePingJob: ({sendTo, nodeId}, callback) =>
    @client.get "interval/ping/#{sendTo}/#{nodeId}", (error, jobId) =>
      return callback error if error?
      @removeJob jobId, callback

  removeJob: (jobId, callback) =>
    return callback() unless jobId?
    @kue.Job.get jobId, (error, job) =>
      job.remove() unless error?
      callback()

module.exports = RegisterJobProcessor
